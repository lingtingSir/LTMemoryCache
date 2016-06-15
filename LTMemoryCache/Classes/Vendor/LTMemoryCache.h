//
//  LTMemoryCache.h
//  LTMemoryCache
//
//  Created by lmj  on 16/6/12.
//  Copyright © 2016年 linmingjun. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, LTCacheListType) {
    LTCacheListTypeLRU = 0,
    LTCacheListTypeMRU = 1 << 0,
    LTCacheListTypeLRUGhost = 1 << 1,
};

@interface LTMemoryCache : NSObject

#pragma mark - Attribute

@property (nonatomic, readonly) LTCacheListType type;

@property (nullable, copy) NSString *name;

@property (readonly) NSUInteger totalCount;

@property (readonly) NSUInteger totalCost;

#pragma mark - Init Method
- (instancetype)initWithCache:(LTCacheListType )type;

#pragma mark - Limit

@property NSUInteger countLimit;

@property NSUInteger costLimit;

@property NSTimeInterval ageLimit;

@property NSTimeInterval autoTrimInterval;

@property BOOL shouldRemoveAllObjectsOnMemoryWarning;

@property BOOL shouldRemoveAllObjectsWhenEnteringBackground;

@property (nullable, copy) void(^didReceiveMemoryWarningBlock)(LTMemoryCache *cache);

@property (nullable, copy) void(^didEnterBackgroundBlock)(LTMemoryCache *cache);

@property BOOL releaseOnMainThread;

@property BOOL releaseAsynchronously;

#pragma mark - Access Methods

- (BOOL)containsObjectForKey:(id)key;

- (nullable id)objectForKey:(id)key;

- (void)setObject:(nullable id)object forKey:(id)key;

- (void)setObject:(nullable id)object forKey:(id)key withCost:(NSUInteger)cost;

- (void)removeObjectForKey:(id)key;

- (void)removeAllObjects;

#pragma mark - Trim

- (void)trimToCount:(NSUInteger)count;

- (void)trimToCost:(NSUInteger)cost;

- (void)trimToAge:(NSTimeInterval)age;

@end

NS_ASSUME_NONNULL_END

