//
//  ViewController.m
//  MLHttpDNSDemo
//
//  Created by molon on 2017/5/4.
//  Copyright © 2017年 molon. All rights reserved.
//

#import "ViewController.h"
#import "MLHttpDNS.h"
#import <sys/time.h>
#import <AFNetworking.h>

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    [MLHttpDNS sharedInstance].enableLog = YES;
    [[MLHttpDNS sharedInstance] setQueryIPsWithRemoteDNSBlock:^(NSString *host,void (^completion)(NSSet *ips)) {
        static AFHTTPSessionManager *manager;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            manager = [AFHTTPSessionManager manager];
            NSMutableSet *contentTypes = [manager.responseSerializer.acceptableContentTypes mutableCopy];
            [contentTypes addObject:@"text/html"];
            AFHTTPResponseSerializer *serializer = [AFHTTPResponseSerializer new];
            serializer.acceptableContentTypes = [NSSet setWithObjects:@"text/html",nil];
            manager.responseSerializer = serializer;
        });
        
        [manager GET:[NSString stringWithFormat:@"http://119.29.29.29/d"] parameters:@{@"dn":host} progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
            if ([responseObject isKindOfClass:[NSData class]]&&((NSData*)responseObject).length>0) {
                NSString *content = [[NSString alloc]initWithData:responseObject encoding:NSUTF8StringEncoding];
                NSArray *es = [content componentsSeparatedByString:@","];
                NSString *ipsContent = [es firstObject];
                NSArray *ips = [ipsContent componentsSeparatedByString:@";"];
                completion(ips.count>0?[NSSet setWithArray:ips]:nil);
            }
        } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
            completion(nil);
        }];
    }];
}

- (IBAction)clickQueryIPsWithLocalDNS:(id)sender {
    struct timeval t0;
    gettimeofday(&t0, NULL);
    [[MLHttpDNS sharedInstance]queryIPFromHost:@"diufan.com" nilWithHTTPProxy:YES completion:^(NSString *ip) {
        struct timeval t1;
        gettimeofday(&t1, NULL);
        double ms = (double)(t1.tv_sec - t0.tv_sec) * 1e3 + (double)(t1.tv_usec - t0.tv_usec) * 1e-3;
        NSLog(@"time:%.2fms\n%@",ms,ip);
    }];
}

@end
