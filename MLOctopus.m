//
//  MLOctopus.m
//  MLModuleExample
//
//  Created by lxy on 2017/10/25.
//  Copyright © 2017年 lxy. All rights reserved.
//

#import "MLOctopus.h"
#import <CommonCrypto/CommonDigest.h>
#import <MapKit/MapKit.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#import <sys/utsname.h>
#import "zlib.h"

#define MLOctpous_SafeString(string) (([@"<null>" isEqualToString:string] || string == nil || [string isKindOfClass:[NSNull class]]) ? @"" : string)

static NSString *const defaultUrl = @"https://bzy.mljr.com/app/v2/gzipPush";

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_9_0 //区分SDK版本
#import <Contacts/Contacts.h>
#import <AddressBook/AddressBook.h>
#else
#import <AddressBook/AddressBook.h>
#endif


@interface MLOctopus () <CLLocationManagerDelegate>

@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) NSMutableDictionary *infoMutDict;

@end


@implementation MLOctopus

#pragma mark - SharedInstance
+ (instancetype)sharedInstance
{
    static id _sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[[self class] alloc] init];
    });
    return _sharedInstance;
}

#pragma mark - PrivateMethod/定位
- (CLLocationManager *)locationManager
{
    if (!_locationManager) {
        _locationManager = [[CLLocationManager alloc] init];
        _locationManager.delegate = self;
        _locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        [_locationManager requestAlwaysAuthorization];
        _locationManager.distanceFilter = 100.0f;
    }
    return _locationManager;
}

//开始定位
- (void)startLocation
{
    [self.locationManager startUpdatingLocation];
}

#pragma mark - getContactsInfo/获取通讯录信息、无UI
- (void)uploadUserInfoWithChannel:(NSString *)channel
                           userId:(NSString *_Nullable)userId
                          capture:(NSString *)capture
                completionHandler:(nullable UploadCompletionHandler)completionHandler
{
    self.infoMutDict = [[NSMutableDictionary alloc] init];
    [self.infoMutDict setObject:channel forKey:@"channel"];
    [self.infoMutDict setObject:capture forKey:@"capture"];
    if (userId) {
        [self.infoMutDict setObject:userId forKey:@"userId"];
    }
    //获取环境信息
    NSMutableDictionary *captureEnvDict = [[NSMutableDictionary alloc] init];
    [captureEnvDict setObject:@"iOS" forKey:@"os"];
    [captureEnvDict setObject:[self getSystemVersion] forKey:@"osVersion"];
    [captureEnvDict setObject:[self getNetWorkStatus] forKey:@"network"];
    [captureEnvDict setObject:[self getDeviceType] forKey:@"product"];
    [captureEnvDict setObject:[self getCarrier] forKey:@"simOperator"];
    [captureEnvDict setObject:[self getUUID] forKey:@"imei"];
    //获取应用基础信息
    NSMutableDictionary *currAppInfoDict = [[NSMutableDictionary alloc] init];
    [currAppInfoDict setObject:[self getBundleName] forKey:@"appName"];
    [currAppInfoDict setObject:[self getBundleVersion] forKey:@"versionName"];
    [currAppInfoDict setObject:[self getBundleIdentifier] forKey:@"packageName"];
    [captureEnvDict setObject:currAppInfoDict forKey:@"currAppInfo"];
    [self.infoMutDict setObject:captureEnvDict forKey:@"captureEnv"];
    //获取经纬度信息
    [self startLocation];

    //获取通讯录信息
    NSMutableDictionary *authStatusDict = [[NSMutableDictionary alloc] init];
    [self.infoMutDict setObject:@{@"addressBookInfoList":@"fullAmount"} forKey:@"captureType"];
    //通讯录详细信息
    [self checkContactsGranted:^(BOOL granted) {
        if (!granted) {
            //无访问权限
            [authStatusDict setObject:@(-1) forKey:@"addressBookInfoList"];
            [self.infoMutDict setObject:authStatusDict forKey:@"authStatus"];
        } else {
            [authStatusDict setObject:@(1) forKey:@"addressBookInfoList"];
            [self.infoMutDict setObject:authStatusDict forKey:@"authStatus"];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_9_0
            if ([[self getSystemVersion] floatValue] >= 9) {
                [self getContactsInfoGreateThanOrEqualIOS9];
            } else {
                [self getContactsLessIOS9];
            }
#else
            [self getContactsLessIOS9:captureDataDict];
#endif
        }
    }];
    //上传统计数据 2秒后上传，2秒期间获取地理位置，不管获取到结果进行上传
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self uploadInfoWithCompletionHandler:completionHandler];
    });
}

#pragma mark - get/通讯录数据
- (void)getContactsInfoGreateThanOrEqualIOS9 {
    if (@available(iOS 9.0, *)) {
        NSMutableArray *dataContentArray = [[NSMutableArray alloc] init];
        CNContactStore *store = [[CNContactStore alloc] init];
        // 创建联系人信息的请求对象
        NSArray *keys = @[CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactOrganizationNameKey, CNContactJobTitleKey, CNContactBirthdayKey,CNContactPhoneNumbersKey, CNContactNoteKey, CNContactPostalAddressesKey,CNContactEmailAddressesKey,CNContactSocialProfilesKey];
        // 根据请求Key, 创建请求对象
        CNContactFetchRequest *request = [[CNContactFetchRequest alloc] initWithKeysToFetch:keys];
        // 发送请求
        [store enumerateContactsWithFetchRequest:request error:nil usingBlock:^(CNContact *_Nonnull contact, BOOL *_Nonnull stop) {
            NSMutableDictionary *storeDict = [[NSMutableDictionary alloc] init];
            //获取姓名
            NSString *givenName = contact.givenName;   //姓
            NSString *familyName = contact.familyName; //名
            NSString *name = [NSString stringWithFormat:@"%@%@", givenName, familyName];
            [storeDict setObject:MLOctpous_SafeString(name) forKey:@"name"];
            [storeDict setObject:MLOctpous_SafeString(contact.nickname) forKey:@"nickName"];
            [storeDict setObject:MLOctpous_SafeString(contact.organizationName) forKey:@"company"];
            [storeDict setObject:MLOctpous_SafeString(contact.jobTitle) forKey:@"position"];
            [storeDict setObject:MLOctpous_SafeString(contact.note) forKey:@"remark"];
            [storeDict setObject:MLOctpous_SafeString([self getTimeStringWith:contact.birthday.date]) forKey:@"dateOfBirth"];

            //获取电话
            NSMutableArray *phoneArray = [[NSMutableArray alloc] init];
            [contact.phoneNumbers enumerateObjectsUsingBlock:^(CNLabeledValue<CNPhoneNumber *> *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
                NSMutableDictionary *phoneMutDict = [[NSMutableDictionary alloc] init];
                CNPhoneNumber *number = obj.value;
                NSString *localLabel = [CNLabeledValue localizedStringForLabel:obj.label];
                [phoneMutDict setObject:MLOctpous_SafeString(localLabel) forKey:@"type"];
                [phoneMutDict setObject:MLOctpous_SafeString(number.stringValue) forKey:@"phoneNumber"];
                [phoneArray addObject:phoneMutDict];
            }];
            if (phoneArray.count > 0) {
                [storeDict setObject:phoneArray forKey:@"phone"];
            }
            //地址获取
            NSMutableArray *addressesArray = [[NSMutableArray alloc] init];
            [contact.postalAddresses enumerateObjectsUsingBlock:^(CNLabeledValue<CNPostalAddress *> *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
                NSMutableDictionary *mutDict = [[NSMutableDictionary alloc] init];
                CNPostalAddress *address = obj.value;
                NSString *localLabel = [CNLabeledValue localizedStringForLabel:obj.label];
                [mutDict setObject:MLOctpous_SafeString(localLabel) forKey:@"type"];
                [mutDict setObject:MLOctpous_SafeString(address.state) forKey:@"province"];
                [mutDict setObject:MLOctpous_SafeString(address.city) forKey:@"city"];
                [mutDict setObject:MLOctpous_SafeString(address.street) forKey:@"district"];
                [addressesArray addObject:mutDict];
            }];
            if (addressesArray.count > 0) {
                [storeDict setObject:addressesArray forKey:@"address"];
            }
            [dataContentArray addObject:storeDict];
            
            //邮件
            NSMutableArray *emailArray = [[NSMutableArray alloc] init];
            [contact.emailAddresses enumerateObjectsUsingBlock:^(CNLabeledValue<NSString *> * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSMutableDictionary *mutDict = [[NSMutableDictionary alloc] init];
                NSString *localLabel = [CNLabeledValue localizedStringForLabel:obj.label];
                [mutDict setObject:MLOctpous_SafeString(localLabel) forKey:@"emailAddress"];
                [emailArray addObject:mutDict];
            }];
            if (emailArray.count > 0) {
                [storeDict setObject:emailArray forKey:@"email"];
            }
            [dataContentArray addObject:storeDict];
            
            //社交
            NSMutableArray *socialArray = [[NSMutableArray alloc] init];
            [contact.socialProfiles enumerateObjectsUsingBlock:^(CNLabeledValue<CNSocialProfile *> * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSMutableDictionary *mutDict = [[NSMutableDictionary alloc] init];
                CNSocialProfile *number = obj.value;
                NSString *localLabel = [CNLabeledValue localizedStringForLabel:obj.label];
                [mutDict setObject:MLOctpous_SafeString(localLabel) forKey:@"type"];
                [mutDict setObject:MLOctpous_SafeString(number.urlString) forKey:@"snsAccoun"];
                [socialArray addObject:mutDict];
            }];
            if (socialArray.count > 0) {
                [storeDict setObject:socialArray forKey:@"sns"];
            }
            [dataContentArray addObject:storeDict];
        }];
        [self.infoMutDict setObject:dataContentArray forKey:@"addressBookInfoList"];
    }
}

- (void)getContactsLessIOS9
{
    NSMutableArray *dataContentArray = [[NSMutableArray alloc] init];
    ABAddressBookRef addBook = nil;
    addBook = ABAddressBookCreateWithOptions(NULL, NULL);
    CFArrayRef allLinkPeople = ABAddressBookCopyArrayOfAllPeople(addBook);
    CFIndex number = ABAddressBookGetPersonCount(addBook);
    for (NSInteger i = 0; i < number; i++) {
        @autoreleasepool
        {
            NSMutableDictionary *storeDict = [[NSMutableDictionary alloc] init];
            //获取联系人对象的引用
            ABRecordRef people = CFArrayGetValueAtIndex(allLinkPeople, i);
            //获取当前联系人名字
            NSString *firstName = (__bridge NSString *)(ABRecordCopyValue(people, kABPersonFirstNameProperty));
            //获取当前联系人姓氏
            NSString *lastName = (__bridge NSString *)(ABRecordCopyValue(people, kABPersonLastNameProperty));
            NSString *nickname = (__bridge NSString *)(ABRecordCopyValue(people, kABPersonNicknameProperty));
            NSString *organizationName = (__bridge NSString *)(ABRecordCopyValue(people, kABPersonOrganizationProperty));
            NSString *jobTitle = (__bridge NSString *)(ABRecordCopyValue(people, kABPersonJobTitleProperty));
            NSString *note = (__bridge NSString *)(ABRecordCopyValue(people, kABPersonNoteProperty));
            NSDate *birthday=(__bridge NSDate*)(ABRecordCopyValue(people, kABPersonBirthdayProperty));

            NSString *name = [NSString stringWithFormat:@"%@%@", firstName, lastName];
            [storeDict setObject:MLOctpous_SafeString(name) forKey:@"name"];
            [storeDict setObject:MLOctpous_SafeString(nickname) forKey:@"nickName"];
            [storeDict setObject:MLOctpous_SafeString(organizationName) forKey:@"company"];
            [storeDict setObject:MLOctpous_SafeString(jobTitle) forKey:@"position"];
            [storeDict setObject:MLOctpous_SafeString(note) forKey:@"remark"];
            [storeDict setObject:MLOctpous_SafeString([self getTimeStringWith:birthday]) forKey:@"dateOfBirth"];

            //获取当前联系人的电话 数组
            ABMultiValueRef phones = ABRecordCopyValue(people, kABPersonPhoneProperty);
            NSMutableArray *phoneArray = [[NSMutableArray alloc] init];
            for (NSInteger j = 0; j < ABMultiValueGetCount(phones); j++) {
                NSMutableDictionary *phoneMutDict = [[NSMutableDictionary alloc] init];
                NSString *phoneString = (__bridge NSString *)(ABMultiValueCopyValueAtIndex(phones, j));
                NSString *localLabel = (__bridge NSString *)ABAddressBookCopyLocalizedLabel(ABMultiValueCopyLabelAtIndex(phones, i));
                [phoneMutDict setObject:MLOctpous_SafeString(localLabel) forKey:@"type"];
                [phoneMutDict setObject:MLOctpous_SafeString(phoneString) forKey:@"phoneNumber"];
                [phoneArray addObject:phoneMutDict];
            }
            if (phoneArray.count > 0) {
                [storeDict setObject:phoneArray forKey:@"phone"];
            }
            CFRelease(people);

            //地址获取
            ABMultiValueRef address = ABRecordCopyValue(people, kABPersonAddressProperty);
            NSMutableArray *addressesArray = [[NSMutableArray alloc] init];
            for (NSInteger i = 0; i < ABMultiValueGetCount(address); i++) {
                NSDictionary *dictionary = (__bridge NSDictionary *)ABMultiValueCopyValueAtIndex(address, i);

                NSMutableDictionary *mutDict = [[NSMutableDictionary alloc] init];
                NSString *localLabel = (__bridge NSString *)ABAddressBookCopyLocalizedLabel((ABMultiValueCopyLabelAtIndex(address, i)));
                NSString *state = [dictionary valueForKey:(__bridge NSString *)kABPersonAddressStateKey];
                NSString *city = [dictionary valueForKey:(__bridge NSString *)kABPersonAddressCityKey];
                NSString *street = [dictionary valueForKey:(__bridge NSString *)kABPersonAddressStreetKey];
                [mutDict setObject:MLOctpous_SafeString(localLabel) forKey:@"type"];
                [mutDict setObject:MLOctpous_SafeString(state) forKey:@"province"];
                [mutDict setObject:MLOctpous_SafeString(city) forKey:@"city"];
                [mutDict setObject:MLOctpous_SafeString(street) forKey:@"district"];
                [addressesArray addObject:mutDict];
            }
            if (addressesArray.count > 0) {
                [storeDict setObject:addressesArray forKey:@"address"];
            }
            [dataContentArray addObject:storeDict];
            CFRelease(address);
            
            //邮件
            ABMultiValueRef emails = ABRecordCopyValue(people, kABPersonEmailProperty);
            NSMutableArray *emailsArray = [[NSMutableArray alloc] init];
            for (NSInteger i = 0; i < ABMultiValueGetCount(emails); i++) {
                NSString *email = (__bridge NSString *)(ABMultiValueCopyValueAtIndex(emails, i));
                NSMutableDictionary *mutDict = [[NSMutableDictionary alloc] init];
                [mutDict setObject:MLOctpous_SafeString(email) forKey:@"emailAddress"];
                [emailsArray addObject:mutDict];
            }
            if (emailsArray.count > 0) {
                [storeDict setObject:emailsArray forKey:@"email"];
            }
            [dataContentArray addObject:storeDict];
            CFRelease(emails);
            
            //社交
            ABMultiValueRef socials = ABRecordCopyValue(people, kABPersonSocialProfileProperty);
            NSMutableArray *socialArray = [[NSMutableArray alloc] init];
            for (NSInteger i = 0; i < ABMultiValueGetCount(socials); i++) {
                NSString *social = (__bridge NSString *)(ABMultiValueCopyValueAtIndex(socials, i));
                NSMutableDictionary *mutDict = [[NSMutableDictionary alloc] init];
                NSString *localLabel = (__bridge NSString *)ABAddressBookCopyLocalizedLabel(ABMultiValueCopyLabelAtIndex(phones, i));
                [mutDict setObject:MLOctpous_SafeString(localLabel) forKey:@"type"];
                [mutDict setObject:MLOctpous_SafeString(social) forKey:@"snsAccoun"];
                [socialArray addObject:mutDict];
            }
            if (emailsArray.count > 0) {
                [storeDict setObject:emailsArray forKey:@"sns"];
            }
            [dataContentArray addObject:storeDict];
            CFRelease(emails);
        }
    }
    [self.infoMutDict setObject:@[dataContentArray] forKey:@"addressBookInfoList"];
}
#pragma mark - check/获取通讯录权限
- (void)checkContactsGranted:(void (^)(BOOL granted))completeBlock
{
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_9_0
    if ([[self getSystemVersion] floatValue] >= 9) {
        [self checkContactsGrantedGreaterThanOrEqualIOS9:completeBlock];
    } else {
        [self checkContactsGrantedLessIOS9:completeBlock];
    }
#else
    [self checkContactsGrantedLessIOS9:completeBlock];
#endif
}

- (void)checkContactsGrantedGreaterThanOrEqualIOS9:(void (^)(BOOL s))completeBlock
{
    if (@available(iOS 9.0, *)) {
        CNContactStore *store = [[CNContactStore alloc] init];
        if ([CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts] == CNAuthorizationStatusNotDetermined) {
            [store requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError *__nullable error) {
                if (granted) {
                    //授权成功
                    completeBlock(YES);
                } else {
                    //授权失败及错误
                    completeBlock(NO);
                }
            }];
        } else if ([CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts] == CNAuthorizationStatusAuthorized) {
            completeBlock(YES);
        } else {
            completeBlock(NO);
        }
    } else {
        // Fallback on earlier versions
    }
}

- (void)checkContactsGrantedLessIOS9:(void (^)(BOOL granted))completeBlock {
    NSInteger __block tip = 0;
    ABAddressBookRef addBook = nil;
    //创建通讯簿的引用，第一个参数暂时写NULL，第二个参数是error参数
    CFErrorRef error = NULL;
    addBook = ABAddressBookCreateWithOptions(NULL, &error);
    //创建一个初始信号量为0的信号
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    //申请访问权限
    ABAddressBookRequestAccessWithCompletion(addBook, ^(bool greanted, CFErrorRef error) {
        //greanted为YES是表示用户允许，否则为不允许
        if (!greanted) {
            tip = 1;
        } else {
            completeBlock(YES);
        }
        //发送一次信号
        dispatch_semaphore_signal(sema);
    });
    //等待信号触发
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    if (tip) {
        completeBlock(NO);
    }
}

#pragma mark - UploadData
- (void)uploadInfoWithCompletionHandler:(nullable UploadCompletionHandler)completionHandler
{
    [self md5StringVerifyWithComplete:^(BOOL md5IsChange, NSString *md5String) {
        if (md5IsChange) {
            [self.infoMutDict setObject:[NSNumber numberWithDouble:[self getCaptureTimeInterval]] forKey:@"captureTime"];
            //serialNo 为去除captureTime及serialNo字段的MD5值用于排除重复上传及部分上传出现的问题
            [self.infoMutDict setObject:MLOctpous_SafeString(md5String) forKey:@"serialNo"];
            NSError *parseError = nil;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self.infoMutDict options:NSJSONWritingPrettyPrinted error:&parseError];
            NSLog(@"json:%@",[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]);
            NSURL *url = [NSURL URLWithString:self.url ? self.url : defaultUrl];
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
            request.HTTPMethod = @"POST";
            [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
            request.HTTPBody = [self gzipDeflate:jsonData];
            NSURLSession *session = [NSURLSession sharedSession];
            NSURLSessionDataTask *sessionDataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable error) {
                if (!error) {
                    //上传成功
                    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:(NSJSONReadingMutableLeaves) error:nil];
                    NSLog(@"%@", dict);
                    if (completionHandler) {
                        completionHandler(dict, nil);
                    }
                } else {
                    if (completionHandler) {
                        completionHandler(nil, error);
                    }
                }
            }];
            [sessionDataTask resume];
        }
    }];
}

#pragma mark - CLLocationManagerDelegate
- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status
{
    switch (status) {
        case kCLAuthorizationStatusNotDetermined:
            if ([self.locationManager respondsToSelector:@selector(requestAlwaysAuthorization)]) {
                [self.locationManager requestWhenInUseAuthorization];
            }
            break;
        default:
            break;
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations
{
    NSMutableDictionary *locationMutDict = [[NSMutableDictionary alloc] init];

    CLLocation *newLocation = locations[0];
    CLLocationCoordinate2D coordinate = newLocation.coordinate;
    NSLog(@"经度：%f,纬度：%f", coordinate.longitude, coordinate.latitude);
    [locationMutDict setObject:[NSString stringWithFormat:@"%f",coordinate.longitude] forKey:@"gpsLongitude"];
    [locationMutDict setObject:[NSString stringWithFormat:@"%f",coordinate.latitude] forKey:@"gpsLatitude"];
    [manager stopUpdatingLocation];
    CLGeocoder *geocoder = [[CLGeocoder alloc] init];
    [geocoder reverseGeocodeLocation:newLocation completionHandler:^(NSArray<CLPlacemark *> *_Nullable placemarks, NSError *_Nullable error) {
        for (CLPlacemark *place in placemarks) {
            NSString *placeString = [NSString stringWithFormat:@"%@%@%@", place.locality, place.subLocality, place.thoroughfare];
            [locationMutDict setObject:MLOctpous_SafeString(placeString) forKey:@"gpsAddress"];
        }
        NSMutableDictionary *captureEnv = [self.infoMutDict objectForKey:@"captureEnv"];
        [captureEnv setObject:locationMutDict forKey:@"gps"];
        [self.infoMutDict setObject:captureEnv forKey:@"captureEnv"];
    }];
}

#pragma mark - PrivateMethod
- (void)md5StringVerifyWithComplete:(void (^)(BOOL md5IsChange, NSString *md5String))complete
{
    NSError *parseError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self.infoMutDict options:NSJSONWritingPrettyPrinted error:&parseError];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSString *md5String = [NSString stringWithFormat:@"json=%@", jsonString];
    NSString *saveMD5String = [[NSUserDefaults standardUserDefaults] objectForKey:@"md5String"];
    if (![saveMD5String isEqualToString:[self md5:md5String]]) {
        [[NSUserDefaults standardUserDefaults] setObject:[self md5:md5String] forKey:@"md5String"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        complete(YES, [self md5:md5String]);
    } else {
        complete(NO, [self md5:md5String]);
    }
}

- (NSString *)getCarrier {
    CTTelephonyNetworkInfo *telephonyInfo = [[CTTelephonyNetworkInfo alloc] init];
    CTCarrier *carrier = [telephonyInfo subscriberCellularProvider];
    NSString *currentCountry = [carrier carrierName];
    return MLOctpous_SafeString(currentCountry);
}

- (NSString *)getNetWorkStatus {
    NSLog(@"%@", [NSThread currentThread]);
    // 状态栏是由当前app控制的，首先获取当前app,局限性：隐藏statusBar无法获取
    UIApplication *app = [UIApplication sharedApplication];
    NSArray *children = [[[app valueForKeyPath:@"statusBar"] valueForKeyPath:@"foregroundView"] subviews];
    NSInteger type = 0;
    for (id child in children) {
        if ([child isKindOfClass:NSClassFromString(@"UIStatusBarDataNetworkItemView")]) {
            type = [[child valueForKeyPath:@"dataNetworkType"] intValue];
        }
    }
    switch (type) {
        case 1:
            return @"2G";
            break;
        case 2:
            return @"3G";
        case 3:
            return @"4G";
        case 5:
            return @"WIFI";
        default:
            return @"unknown"; //代表未知网络
            break;
    }
}

- (NSString *)md5:(NSString *)input {
    const char *cStr = [input UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, (CC_LONG)strlen(cStr), digest);
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (NSInteger i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
        [output appendFormat:@"%02x", digest[i]];
    return output;
}

- (NSString *)getTimeStringWith:(NSDate *)date {
    if (!date) {
        return @"";
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm";
    return [formatter stringFromDate:date];
}

- (long long)getCaptureTimeInterval {
  return (NSUInteger)[[NSDate date]timeIntervalSince1970] * 1000;
}

- (NSString *)getSystemVersion {
    return [[UIDevice currentDevice] systemVersion];
}

- (NSString *)getUUID {
    return [[[UIDevice currentDevice] identifierForVendor] UUIDString];
}

- (NSString *)getBundleName {
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:(__bridge NSString *)kCFBundleNameKey];
}

- (NSString *)getBundleIdentifier {
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:(__bridge NSString *)kCFBundleIdentifierKey];
}

- (NSString *)getBundleVersion {
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:(__bridge NSString *)kCFBundleVersionKey];
}

- (NSString*)getDeviceType {
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *platform = [NSString stringWithCString:systemInfo.machine encoding:NSASCIIStringEncoding];
    //采用后台映射
    return platform;
}

//gzip压缩
- (NSData *)gzipDeflate:(NSData *)data {
    if ([data length] == 0) return data;
    z_stream strm;
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    strm.opaque = Z_NULL;
    strm.total_out = 0;
    strm.next_in = (Bytef *)[data bytes];
    strm.avail_in = (uInt)[data length];
    if (deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, (15 + 16), 8, Z_DEFAULT_STRATEGY) != Z_OK) return nil;
    NSMutableData *compressed = [NSMutableData dataWithLength:16384]; // 16K chunks for expansion
    do {
        if (strm.total_out >= [compressed length])
            [compressed increaseLengthBy:16384];
        strm.next_out = [compressed mutableBytes] + strm.total_out;
        strm.avail_out = (uInt)([compressed length] - strm.total_out);
        deflate(&strm, Z_FINISH);
    } while (strm.avail_out == 0);
    deflateEnd(&strm);
    [compressed setLength:strm.total_out];
    return [NSData dataWithData:compressed];
}

@end
