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
 @brief 每隔主机名有效记录的遗弃时间，默认60*5
 */
@property (nonatomic, assign) NSTimeInterval banTime;

/*!
 @brief 是否开启日志
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
