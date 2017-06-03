//
//  MLHttpDNS.m
//  MLHttpDNSDemo
//
//  Created by molon on 2017/5/4.
//  Copyright © 2017年 molon. All rights reserved.
//

#import "MLHttpDNS.h"
#import <arpa/inet.h>
#import <YYCache/YYCache.h>
#import <AFNetworking/AFNetworkReachabilityManager.h>
#import <pthread.h>

NSString * const MLHttpDNSCacheName = @"MLHttpDNSCache";
NSString * const MLHttpDNSHistoryCacheName = @"MLHttpDNSHistoryCache";

#define MLHTTPDNS_PTHREAD_ASSERT_ON_ERROR(x_) do { \
_Pragma("clang diagnostic push"); \
_Pragma("clang diagnostic ignored \"-Wunused-variable\""); \
volatile int res = (x_); \
assert(res == 0); \
_Pragma("clang diagnostic pop"); \
} while (0)

@interface _MLHttpDNSRecord : NSObject<NSCoding>

@property (nonatomic, assign) NSTimeInterval time;
@property (nonatomic, strong) NSSet *ips;

@end

@implementation _MLHttpDNSRecord

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_ips forKey:@"ips"];
    [aCoder encodeDouble:_time forKey:@"time"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _ips = [aDecoder decodeObjectForKey:@"ips"];
    _time = [aDecoder decodeDoubleForKey:@"time"];
    
    return self;
}

- (nullable instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _time = [[NSDate date]timeIntervalSince1970];
    
    return self;
}

- (BOOL)isStaleWithTTL:(NSTimeInterval)ttl {
    NSTimeInterval time = [[NSDate date]timeIntervalSince1970];
    return (time-_time>ttl);
}

@end

@implementation MLHttpDNS {
    YYCache *_cache;
    YYCache *_historyCache;
    
    AFNetworkReachabilityManager *_reachabilityManager;
    pthread_mutex_t _m; //recursive
}

@synthesize expireTime = _expireTime;
@synthesize banTime = _banTime;
@synthesize enableLog = _enableLog;
@synthesize queryIPsWithRemoteDNSBlock = _queryIPsWithRemoteDNSBlock;
@synthesize alwaysLazyQueryFromRemoteDNS = _alwaysLazyQueryFromRemoteDNS;

+ (instancetype)sharedInstance {
    static id _sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[[self class] alloc] init];
    });
    
    return _sharedInstance;
}

#pragma mark - life
- (instancetype)init {
    self = [super init];
    if (self) {
        _expireTime = 50;
        _banTime = 60*3;
        _alwaysLazyQueryFromRemoteDNS = YES;
        _enableLog = NO;
        
        //mutex
        pthread_mutexattr_t attr;
        MLHTTPDNS_PTHREAD_ASSERT_ON_ERROR(pthread_mutexattr_init (&attr));
        MLHTTPDNS_PTHREAD_ASSERT_ON_ERROR(pthread_mutexattr_settype (&attr, PTHREAD_MUTEX_RECURSIVE));
        MLHTTPDNS_PTHREAD_ASSERT_ON_ERROR(pthread_mutex_init (&_m, &attr));
        MLHTTPDNS_PTHREAD_ASSERT_ON_ERROR(pthread_mutexattr_destroy (&attr));
        
        _cache = [YYCache cacheWithName:MLHttpDNSCacheName];
        _historyCache = [YYCache cacheWithName:MLHttpDNSHistoryCacheName];
        _reachabilityManager = [AFNetworkReachabilityManager manager];
        __weak typeof(self)wSelf = self;
        [_reachabilityManager setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
            __strong typeof(self)sSelf = wSelf;
            //只要切换就清空当前所有记录
            [sSelf->_cache removeAllObjects];
        }];
    }
    return self;
}

#pragma mark - setter
- (void)setExpireTime:(NSTimeInterval)expireTime {
    [self lock];
    _expireTime = expireTime;
    [self unlock];
}

- (void)setBanTime:(NSTimeInterval)banTime {
    [self lock];
    _banTime = banTime;
    [self unlock];
}

- (void)setEnableLog:(BOOL)enableLog {
    [self lock];
    _enableLog = enableLog;
    [self unlock];
}

- (void)setQueryIPsWithRemoteDNSBlock:(void (^)(NSString *host,void (^)(NSSet *)))queryIPsWithRemoteDNSBlock {
    [self lock];
    _queryIPsWithRemoteDNSBlock = [queryIPsWithRemoteDNSBlock copy];
    [self unlock];
}

- (void)setAlwaysLazyQueryFromRemoteDNS:(BOOL)alwaysLazyQueryFromRemoteDNS {
    [self lock];
    _alwaysLazyQueryFromRemoteDNS = alwaysLazyQueryFromRemoteDNS;
    [self unlock];
}

#pragma mark - getter
- (NSTimeInterval)expireTime {
    [self lock];
    NSTimeInterval expireTime = _expireTime;
    [self unlock];
    return expireTime;
}

- (NSTimeInterval)banTime {
    [self lock];
    NSTimeInterval banTime = _banTime;
    [self unlock];
    return banTime;
}

- (BOOL)enableLog {
    [self lock];
    BOOL enableLog = _enableLog;
    [self unlock];
    return enableLog;
}

- (void (^)(NSString *,void (^)(NSSet *)))queryIPsWithRemoteDNSBlock {
    [self lock];
    typeof(_queryIPsWithRemoteDNSBlock) queryBlock = _queryIPsWithRemoteDNSBlock;
    [self unlock];
    return queryBlock;
}

- (BOOL)alwaysLazyQueryFromRemoteDNS {
    [self lock];
    BOOL alwaysLazyQueryFromRemoteDNS = _alwaysLazyQueryFromRemoteDNS;
    [self unlock];
    return alwaysLazyQueryFromRemoteDNS;
}

#pragma mark - mutex
- (void)lock {
    MLHTTPDNS_PTHREAD_ASSERT_ON_ERROR(pthread_mutex_lock(&_m));
}

- (void)unlock {
    MLHTTPDNS_PTHREAD_ASSERT_ON_ERROR(pthread_mutex_unlock(&_m));
}

#pragma mark - outcall
- (void)queryIPFromHost:(NSString*)host nilWithHTTPProxy:(BOOL)nilWithHTTPProxy completion:(void(^)(NSString *ip))completion {
    NSAssert(completion, @"completion of `queryIPFromHost:completion:` cant be nil");
    NSAssert(host.length>0, @"host of `queryIPFromHost:completion:` is not valid");
    
    host = [host lowercaseString];
    
    __block BOOL ended = NO;
    void(^endBlock)(NSString *ip) = ^(NSString *ip){
        if (ended) {
            return;
        }
        ended = YES;
        
        if (self.enableLog) {
            NSLog(@"[MLHttpDNS] Return IP for %@:%@",host,ip);
        }
        
        //最后回到主线程返回
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(ip);
        });
    };
    
    //如果处于HTTP代理环境那就直接返回nil，不能使用直连IP服务
    if (nilWithHTTPProxy&&[MLHttpDNS isUsingHTTPProxy]) {
        endBlock(nil);
        return;
    }
    
    //首先判断当前是否已经存在没过期的结果了，有就无需进行query
    [_cache objectForKey:host withBlock:^(NSString * _Nonnull key, id _Nonnull object) {
        _MLHttpDNSRecord *r = nil;
        if ([object isKindOfClass:[_MLHttpDNSRecord class]]) {
            r = (_MLHttpDNSRecord*)object;
            if (![r isStaleWithTTL:self.expireTime]) {
                endBlock([r.ips anyObject]);
                return;
            }
        }
        
        void(^cacheCurrentRecord)(NSSet *) = ^(NSSet *ips){
            [self lock];
            if (ips.count<=0) {
                [_cache removeObjectForKey:host];
            }else{
                _MLHttpDNSRecord *record = [_MLHttpDNSRecord new];
                record.ips = ips;
                [_cache setObject:record forKey:host];
            }
            if (_enableLog) {
                NSLog(@"[MLHttpDNS] Cache IPs For %@ (ttl:%.0lf):\n%@",host,_expireTime,ips);
            }
            [self unlock];
        };
        
        //从LocalDNS拿取
        if (self.enableLog) {
            NSLog(@"[MLHttpDNS] Begin query IPs with local dns for %@",host);
        }
        
        [self queryIPsWithLocalDNSFromHost:host completion:^(NSSet *localIPs) {
            [self lock];
            
            NSMutableSet *validIPs = [NSMutableSet setWithCapacity:localIPs.count];
            //和历史绝对有效记录比对，剔除无效的
            for (NSString *ip in localIPs) {
                if ([_historyCache containsObjectForKey:[self historyCacheKeyWithHost:host ip:ip]]) {
                    [validIPs addObject:ip];
                }
            }
            
            if (_enableLog) {
                NSLog(@"[MLHttpDNS] Get %lu IPs from local dns for %@, validIPs count:%lu",(unsigned long)localIPs.count,host,(unsigned long)validIPs.count);
            }
            
            //说明至少LocalDNS返回的一些IP曾经被验证过可用，这里直接认为有效返回即可。
            if (validIPs.count>0) {
                [self unlock];
                
                //存储下来
                cacheCurrentRecord(validIPs);
                endBlock([validIPs anyObject]);
                return;
            }
            
            //到这里可以就先认作是被劫持了，(也不一定，有可能历史有效记录并未记录所有域名，这很正常，但是不影响下面的逻辑，其记录一次后即可正常)
            //如果有过期还未遗弃的缓存，就直接返回过期缓存，保证请求的正常快速执行，下面第三方服务去尽可能的异步更新缓存，即使第三方服务后续一直挂了，也会触发下一个行为
            if (r&&![r isStaleWithTTL:_banTime]) {
                endBlock([r.ips anyObject]);
            }else{
                //若打开了此开关，那就先返回本地DNS获取的那些用着，这会的话有丢丢可能让用户遇到被劫持情况，但是只要远程DNS可用，用户重新请求就可恢复正常
                if (_alwaysLazyQueryFromRemoteDNS) {
                    endBlock([localIPs anyObject]);
                }
            }
            
            //如果并未存在过期还未遗弃的缓存，RemoteDNS又挂了的话，最后会直接返回nil让外界按原始行为请求，管不了了，等第三方服务又有效的时候，自然而然就动起来了。
            if (_enableLog) {
                NSLog(@"[MLHttpDNS] Begin query IPs with remote dns for %@",host);
            }
            
            [self unlock];
            
            [self queryIPsWithRemoteDNSFromHost:host completion:^(NSSet *remoteIPs) {
                //将这些IP作为历史绝对有效记录来看
                for (NSString *ip in remoteIPs) {
                    [_historyCache setObject:@(YES) forKey:[self historyCacheKeyWithHost:host ip:ip]];
                }
                
                if (self.enableLog) {
                    NSLog(@"[MLHttpDNS] Get %lu IPs from remote dns for %@",(unsigned long)remoteIPs.count,host);
                }
                
                cacheCurrentRecord(remoteIPs);
                endBlock([remoteIPs anyObject]);
            }];
        }];
    }];
}

#pragma mark - cache
- (NSString*)historyCacheKeyWithHost:(NSString*)host ip:(NSString*)ip {
    return [NSString stringWithFormat:@"%@-%@",host,ip];
}

#pragma mark - query
void _MLHttpDNS_CFHostClientCallbackFunction(CFHostRef theHost, CFHostInfoType typeInfo, const CFStreamError *error, void *info) {
    void(^endBlock)(NSSet *) = ^(NSSet *ips){
        if (error!=NULL&&(error->domain!=0||error->error!=0)) {
            NSLog(@"Error while `_MLHttpDNS_CFHostClientCallbackFunction`: %d (domain:%ld)",(int)error->error,(long)error->domain);
        }
        
        void(^completion)(NSSet *) = (__bridge typeof(completion))info;
        if (completion) {
            completion(ips);
        }
        
        CFHostUnscheduleFromRunLoop(theHost, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        CFHostSetClient(theHost, NULL, NULL);
    };
    
    if (!info||typeInfo!=kCFHostAddresses) {
        endBlock(nil);
        return;
    }
    
    Boolean ret = NO;
    CFArrayRef addresses = CFHostGetAddressing(theHost, &ret);
    if (!addresses) {
        endBlock(nil);
        return;
    }
    
    NSMutableSet *ips = [NSMutableSet setWithCapacity:1];
    struct sockaddr_in *remoteAddr;
    for(int i = 0; i < CFArrayGetCount(addresses); i++) {
        CFDataRef saData = (CFDataRef)CFArrayGetValueAtIndex(addresses, i);
        remoteAddr = (struct sockaddr_in*)CFDataGetBytePtr(saData);
        
        if(remoteAddr != NULL) {
            char ip[16];
            strcpy(ip, inet_ntoa(remoteAddr->sin_addr));
            [ips addObject:[NSString stringWithCString:ip encoding:NSUTF8StringEncoding]];
        }
    }
    
    endBlock(ips.count>0?ips:nil);
}

- (void)queryIPsWithLocalDNSFromHost:(NSString*)host completion:(void(^)(NSSet *ips))completion {
    NSAssert(completion, @"completion of `queryIPsWithLocalDNSFromHost:completion:` cant be nil");
    
    CFHostRef hostRef = CFHostCreateWithName(kCFAllocatorDefault, (__bridge CFStringRef)host);
    if (!hostRef) {
        completion(nil);
        return;
    }
    
    NS_VALID_UNTIL_END_OF_SCOPE typeof(completion) completionCopy = [completion copy]; //一定要保证在CFHostSetClient执行前其没有被释放
    CFHostClientContext clientCTX = {
        .version = 0L,
        .info = (__bridge void*)completionCopy,
        //下面俩会让这个block被hostRef持有和释放，其去管理引用
        .retain = (CFAllocatorRetainCallBack)CFRetain,
        .release = (CFAllocatorReleaseCallBack)CFRelease,
        .copyDescription = (CFAllocatorCopyDescriptionCallBack)CFCopyDescription
    };
    
    Boolean ret = CFHostSetClient(hostRef, _MLHttpDNS_CFHostClientCallbackFunction, &clientCTX);
    if (!ret) {
        NSLog(@"`CFHostSetClient` failed!");
        
        CFHostSetClient(hostRef, NULL, NULL);
        completion(nil);
        
        CFRelease(hostRef);
        return;
    }
    
    CFHostScheduleWithRunLoop(hostRef, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    
    CFStreamError error;
    ret = CFHostStartInfoResolution(hostRef, kCFHostAddresses, &error);
    if (!ret) {
        NSLog(@"Error while `CFHostStartInfoResolution`: %d (domain:%ld)",(int)error.error,(long)error.domain);
        
        CFHostUnscheduleFromRunLoop(hostRef, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        CFHostSetClient(hostRef, NULL, NULL);
        completion(nil);
    }
    
    CFRelease(hostRef); //此方法内部用完它了就解除引用
}

- (void)queryIPsWithRemoteDNSFromHost:(NSString *)host completion:(void (^)(NSSet *ips))completion {
    NSAssert(self.queryIPsWithRemoteDNSBlock, @"queryIPsWithRemoteDNSBlock cant be nil");
    
    self.queryIPsWithRemoteDNSBlock(host,completion);
}

#pragma mark - helper
+ (BOOL)isUsingHTTPProxy {
    CFDictionaryRef dicRef = CFNetworkCopySystemProxySettings();
    const CFStringRef proxyCFstr = (const CFStringRef)CFDictionaryGetValue(dicRef, (const void*)kCFNetworkProxiesHTTPProxy);
    return (proxyCFstr != NULL);
}

@end
