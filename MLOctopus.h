//
//  MLOctopus.h
//  MLModuleExample
//
//  Created by lxy on 2017/10/25.
//  Copyright © 2017年 lxy. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 风控系统用户信息采集，由于苹果的非开源原因，iOS目前可获取的信息为，地理位置信息、通讯录信息（不支持安装应用信息、通话记录、短信内容）
 */
NS_ASSUME_NONNULL_BEGIN

typedef void (^UploadCompletionHandler)(NSDictionary *_Nullable dict, NSError *_Nullable error);


@interface MLOctopus : NSObject

/**
 上传服务器地址，默认URL线上：@"https://bzy.mljr.com/app/gzipPush"
                    测试：@"http://192.168.49.213:18888/app/gzipPush"
 */
@property (nonatomic, copy) NSString *url;


+ (instancetype)sharedInstance;
/**
 获取通讯录权限
 
 @param completeBlock complete   greanted：YES 已授权 ：NO 未授权
 */
- (void)checkContactsGranted:(void (^)(BOOL granted))completeBlock;

/**
 上传用户基础信息
 
 @param channel 业务渠道区分不同APP
 @param userId 用户id 未登录为 nil
 @param capture 采集场景
 @param completionHandler 上传成功block
 */
- (void)uploadUserInfoWithChannel:(NSString *)channel
                           userId:(NSString *_Nullable)userId
                          capture:(NSString *)capture
                completionHandler:(nullable UploadCompletionHandler)completionHandler;

@end

NS_ASSUME_NONNULL_END
