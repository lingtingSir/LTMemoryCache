//
//  ViewController.m
//  DataStorageExample
//
//  Created by lmj  on 16/5/26.
//  Copyright (c) 2016年 linmingjun. All rights reserved.
//

#import "ViewController.h"
#import "LTMemoryCache.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MemoryCache Example";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self memoryCacheBenchmark];
    });
    
    
}


- (void)memoryCacheBenchmark {
    LTMemoryCache *LT = [[LTMemoryCache alloc] initWithCache:LTCacheListTypeLRUGhost];
//    LTMemoryCache *LT = [[LTMemoryCache alloc] initWithCache:LTCacheListTypeMRU];
//    LTMemoryCache *LT = [LTMemoryCache new];
    LT.releaseOnMainThread = YES;
    
    NSMutableArray *keys = [NSMutableArray new];
    NSMutableArray *values = [NSMutableArray new];
    int count = 500000;
    for (int i = 0; i < count; i++) {
        NSObject *key;
        key = @(i);
        NSData *value = [NSData dataWithBytes:&i length:sizeof(int)];
        [keys addObject:key];
        [values addObject:value];
    }
    
    NSTimeInterval begin, end, time;
    
    
    printf("\n===========================\n");
    printf("Memory cache set 200000 key-value pairs\n");
    
    
    
    begin = CACurrentMediaTime();
    @autoreleasepool {
        for (int i = 0; i < count; i++) {
            [LT setObject:values[i] forKey:keys[i]];
        }
    }
    end = CACurrentMediaTime();
    time = end - begin;
    printf("LTMemoryCache:  %8.2f\n", time * 1000);
    
    
    
    
    
    printf("\n===========================\n");
    printf("Memory cache set 200000 key-value pairs without resize\n");
    
    
    
    
    //[LT removeAllObjects]; // it will rebuild inner cache...
    for (id key in keys) [LT removeObjectForKey:key]; // slow than 'removeAllObjects'
    begin = CACurrentMediaTime();
    @autoreleasepool {
        for (int i = 0; i < count; i++) {
            [LT setObject:values[i] forKey:keys[i]];
        }
    }
    end = CACurrentMediaTime();
    time = end - begin;
    printf("LTMemoryCache:  %8.2f\n", time * 1000);
    
    
    
    
    printf("\n===========================\n");
    printf("Memory cache get 200000 key-value pairs\n");
    
    
    
    
    begin = CACurrentMediaTime();
    @autoreleasepool {
        for (int i = 0; i < count; i++) {
            [LT objectForKey:keys[i]];
        }
    }
    end = CACurrentMediaTime();
    time = end - begin;
    printf("LTMemoryCache:  %8.2f\n", time * 1000);
    
    
    
    begin = CACurrentMediaTime();
    @autoreleasepool {
        for (int i = 0; i < count; i++) {
            [LT objectForKey:keys[i]];
        }
    }
    end = CACurrentMediaTime();
    time = end - begin;
    printf("LTMemoryCache:  %8.2f\n", time * 1000);
    
    printf("\n===========================\n");
    printf("Memory cache get 200000 key-value pairs none exist\n");
    for (int i = 0; i < count; i++) {
        NSObject *key;
        key = @(i + count); // avoid string compare
        [keys addObject:key];
    }
    
    for (NSUInteger i = keys.count; i > 1; i--) {
        [keys exchangeObjectAtIndex:(i - 1) withObjectAtIndex:arc4random_uniform((u_int32_t)i)];
    }

    begin = CACurrentMediaTime();
    @autoreleasepool {
        for (int i = 0; i < count; i++) {
            [LT objectForKey:keys[i]];
        }
    }
    end = CACurrentMediaTime();
    time = end - begin;
    printf("LTMemoryCache:  %8.2f\n", time * 1000);
    
}



@end
