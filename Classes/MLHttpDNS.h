//
//  MLHttpDNS.h
//  MLHttpDNSDemo
//
//  Created by molon on 2017/5/4.
//  Copyright © 2017年 molon. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MLHttpDNS : NSObject

/*!
 @brief 外部提供远程获取IP列表的服务，注意超时时间不能过长，2-5秒适宜
 */
@property (nonatomic, copy) void(^queryIPsWithRemoteDNSBlock)(NSString *host,void(^completion)(NSSet *ips));

/*!
 @brief 每个主机名有效记录的过期时间，默认50
 */
@property (nonatomic, assign) NSTimeInterval expireTime;

/*!
 @brief 每个主机名有效记录的遗弃时间，默认60*3
 */
@property (nonatomic, assign) NSTimeInterval banTime;

/*!
 @brief 永远懒请求远程DNS服务器，默认为YES
 @warning 若为YES能保证尽可能的不受RemoteDNS服务的可用性影响，弊端是会有短暂的一两次被劫持可能，若为NO则不会有上述弊端，但是需要去RemoteDNS请求时会等待其返回或者超时才有响应，很受服务的可用性速度等限制。
 */
@property (nonatomic, assign) BOOL alwaysLazyQueryFromRemoteDNS;

/*!
 @brief 是否开启日志，默认为NO
 */
@property (nonatomic, assign) BOOL enableLog;

/*!
 @brief 单例
 
 @return 单例
 */
+ (instancetype)sharedInstance;

/*!
 @brief 通过主机名获取IP
 @warning 如果回调返回nil，请使用原始方式做请求
 
 @param host       主机名
 @param nilWithHTTPProxy 是否在HTTP代理环境下return nil
 @param completion 回调
 */
- (void)queryIPFromHost:(NSString*)host nilWithHTTPProxy:(BOOL)nilWithHTTPProxy completion:(void(^)(NSString *ip))completion;

/*!
 @brief 设置queryIPsWithRemoteDNSBlock定义
 
 @param queryIPsWithRemoteDNSBlock queryIPsWithRemoteDNSBlock
 */
- (void)setQueryIPsWithRemoteDNSBlock:(void (^)(NSString *host, void (^completion)(NSSet *ips)))queryIPsWithRemoteDNSBlock;

@end
