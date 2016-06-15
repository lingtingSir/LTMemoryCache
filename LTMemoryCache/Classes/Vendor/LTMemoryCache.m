//
//  LTMemoryCache.m
//  LTMemoryCache
//
//  Created by lmj  on 16/6/12.
//  Copyright © 2016年 linmingjun. All rights reserved.
//

#import "LTMemoryCache.h"
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <pthread.h>

static inline dispatch_queue_t LTMemoryCacheGetReleaseQueue() {
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
}

@interface _LTLinkedMapNode : NSObject {
    @package
    __unsafe_unretained _LTLinkedMapNode *_prev; // retained by dic
    __unsafe_unretained _LTLinkedMapNode *_next; // retained by dic
    id _key;
    id _value;
    NSUInteger _cost;
    NSTimeInterval _time;
}
@end

@implementation _LTLinkedMapNode
@end

@interface _LTLinkedMap : NSObject {
    
    @package
    CFMutableDictionaryRef _dic;
    LTCacheListType _type;
    NSUInteger _totalCost;
    NSUInteger _totalCount;
    _LTLinkedMapNode *_head;
    _LTLinkedMapNode *_tail;
    BOOL _releaseOnMainThread;
    BOOL _releaseAsynchronously;
}


- (void)insertNodeAtHead:(_LTLinkedMapNode *)node;


- (void)bringNodeToHead:(_LTLinkedMapNode *)node;

- (void)removeNode:(_LTLinkedMapNode *)node;

- (_LTLinkedMapNode *)removeTailNode;

- (void)removeAll;

@end

@implementation _LTLinkedMap

- (instancetype)init {
    self = [super init];
    _dic = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    _releaseOnMainThread = NO;
    _releaseAsynchronously = YES;
    return self;
}




- (void)dealloc {
    CFRelease(_dic);
}

- (void)insertNodeAtHead:(_LTLinkedMapNode *)node {
    CFDictionarySetValue(_dic, (__bridge const void *)(node->_key), (__bridge const void *)(node));
    _totalCost += node->_cost;
    _totalCount++;
    
    if (_head) {
        // 把插入的数据作为头结点
        node->_next = _head;
        // 设置第二个节点（原先头结点的）的前继
        _head->_prev = node;
        // 设置头节点为插入的节点
        _head = node;
    } else { // 如果插入的是第一个数据
        _head = _tail = node;
    }
}

// node移到head（头结点） 每次缓存命中时将页面转移LRU位置（head）
- (void)bringNodeToHead:(_LTLinkedMapNode *)node {
    // 如果该结点是头结点，直接返回
    if (_head == node) return;
    if (_tail == node) {
        // 因为最后一个节点要往（head）头节点移动所以尾节点要指向前一个节点
        _tail = node->_prev;
        _tail->_next = nil;
    } else {
        /**  如果该结点位于链表之间
         */
        // 当前结点的前驱线索指向当前结点的后继
        node->_next->_prev = node->_prev;
        // 当前结点的后继线索指向前驱
        node->_prev->_next = node->_next;
    }
    // 当前结点的后继线索指向头结点，那么head为第二结点
    node->_next = _head;
    // 非循环双向链表，将前继线索置为nil
    node->_prev = nil;
    // 此时的head作为第二个结点，第二个结点前驱线索指向第一个节点
    _head->_prev = node;
    // 头结点指针指向第一个节点
    _head = node;
    /** 如果是双向循环链表：取消 node->_prev = nil; 这行代码
     head->_prev->_next = node;
     node->_next = head;
     */
}

/// 移除内节点和更新的总成本。节点在已经DIC内。
- (void)removeNode:(_LTLinkedMapNode *)node {
    // 从缓冲池中移除指定对象
    CFDictionaryRemoveValue(_dic, (__bridge const void *)(node->_key));
    _totalCost -= node->_cost;
    _totalCount--;
    // 移除节点位于头尾之间
    if (node->_next)
        node->_next->_prev = node->_prev;
    if (node->_prev)
        node->_prev->_next = node->_next;

    // 移除节点是头节点,头结点指向下一个结点
    if (_head == node)
        _head = node->_next;
    // 移除节点是尾节点，尾结点指向前一个结点
    if (_tail == node)
        _tail = node->_prev;
}


- (_LTLinkedMapNode *)removeTailNode {
    if (!_tail) return nil;
    _LTLinkedMapNode *tail = _tail;
    CFDictionaryRemoveValue(_dic, (__bridge const void *)(_tail->_key));
    // 更新的总成本和数据量
    _totalCost -= _tail->_cost;
    _totalCount--;
    if (_head == _tail) {
        _head = _tail = nil;
    } else {
        // 设置尾节点指向前一个节点
        _tail = _tail->_prev;
        // 设置尾节点的后继线索后空。
        _tail->_next = nil;
    }
    // 返回尾节点
    return tail;
}

- (_LTLinkedMapNode *)removeHeadNode {
    if (!_head) return nil;
    _LTLinkedMapNode *head = _head; // 记录头结点
    CFDictionaryRemoveValue(_dic, (__bridge const void *)(_head->_key));
    // 更新的总成本和数据量
    _totalCost -= _head->_cost;
    _totalCount--;
    if (_head == _tail) {
        _head = _tail = nil;
    } else {
        
        // 设置头节点指向后一个节点
        _head = _head->_next;
        // 设置头节点的前驱线索置为nil。
        _head->_prev = nil;
    }
    // 返回头节点
    return head;
}


- (void)removeAll {
    _totalCost = 0;
    _totalCount = 0;
    _head = nil;
    _tail = nil;
    if (CFDictionaryGetCount(_dic) > 0) {
        CFMutableDictionaryRef holder = _dic;
        // 初始化字典
        _dic = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        
        if (_releaseAsynchronously) {
            dispatch_queue_t queue = _releaseOnMainThread ? dispatch_get_main_queue() : LTMemoryCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                CFRelease(holder); // hold and release in specified queue
            });
        } else if (_releaseOnMainThread && !pthread_main_np()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                CFRelease(holder); // hold and release in specified queue
            });
        } else {
            CFRelease(holder);
        }
    }
}

@end



@implementation LTMemoryCache {
    pthread_mutex_t _lock;
    _LTLinkedMap *_lru;
    _LTLinkedMap *_lruGhost;
    dispatch_queue_t _queue;
}

- (void)_trimRecursively {
    __weak typeof(self) _self = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_autoTrimInterval * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        __strong typeof(_self) self = _self;
        if (!self) return;
        [self _trimInBackground];
        [self _trimRecursively];
    });
}

- (void)_trimInBackground {
    dispatch_async(_queue, ^{
        [self _trimToCost:self->_costLimit];
        [self _trimToCount:self->_countLimit];
        [self _trimToAge:self->_ageLimit];
    });
}

#pragma mark - remove/setObjectTrim

- (void)removeAllList {
    switch (LTCacheListTypeLRU) {
        case LTCacheListTypeLRUGhost :
            [_lru removeAll];
            [_lruGhost removeAll];
            break;
        case LTCacheListTypeMRU :
        case LTCacheListTypeLRU :
            [_lru removeAll];
            break;
        default:
            break;
    }
}

- (_LTLinkedMapNode *)removeHeadOrTail {
    _LTLinkedMapNode *node = [_lru removeTailNode];
    switch (_type) {
        case LTCacheListTypeLRUGhost :
            [_lruGhost insertNodeAtHead:node];
            break;
        case LTCacheListTypeMRU :
            node = [_lru removeHeadNode];
        case LTCacheListTypeLRU :
        default:
            break;
    }
    return node;
}

- (void)setObjectLruOrLruGhost:(_LTLinkedMap *)_LruOrLruGhost {
    if (_LruOrLruGhost->_totalCost > _costLimit) {
        dispatch_async(_queue, ^{
            [self trimToCost:_costLimit];
        });
    }
    if (_LruOrLruGhost->_totalCount > _countLimit) {
        
        _LTLinkedMapNode * node = [_LruOrLruGhost removeTailNode];

        if ([_LruOrLruGhost isEqual:_lru]) {
            [_lruGhost insertNodeAtHead:node];
           
        } else {
            if (_lruGhost->_totalCount == _countLimit) {
               
                [_lruGhost removeAll];
                
            }
        }
        if (_LruOrLruGhost->_releaseAsynchronously) {
            dispatch_queue_t queue = _LruOrLruGhost->_releaseOnMainThread ? dispatch_get_main_queue() : LTMemoryCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                [node class];
            });
        } else if (_LruOrLruGhost->_releaseOnMainThread && !pthread_main_np()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [node class];
            });
        }
    }
}



- (void)_trimToCost:(NSUInteger)costLimit {
    BOOL finish = NO;
    pthread_mutex_lock(&_lock);
    if (costLimit == 0) {
        
        [self removeAllList];
        
        finish = YES;
    } else if (_lru->_totalCost <= costLimit) {
        
        finish = YES;
    }
    pthread_mutex_unlock(&_lock);
    if (finish) return;
    
    NSMutableArray *holder = [NSMutableArray new];
    while (!finish) {
        if (pthread_mutex_trylock(&_lock) == 0) {
            if (_lru->_totalCost > costLimit) {
                _LTLinkedMapNode *node = [self removeHeadOrTail];
                if (node) [holder addObject:node];
            } else {
                finish = YES;
            }
            pthread_mutex_unlock(&_lock);
        } else {
            usleep(10 * 1000);
        }
    }
    
    if (holder.count) {
        dispatch_queue_t queue = _lru->_releaseOnMainThread ? dispatch_get_main_queue() : LTMemoryCacheGetReleaseQueue();
        dispatch_async(queue, ^{
          
            [holder count];
        });
    }
}

- (void)_trimToCount:(NSUInteger)countLimit {
    BOOL finish = NO;
    pthread_mutex_lock(&_lock);
    if (countLimit == 0) {
        [self removeAllList];
        finish = YES;
    } else if (_lru->_totalCount  <= countLimit) {
        finish = YES;
    }
    
    pthread_mutex_unlock(&_lock);
    if (finish) return;
    
    NSMutableArray *holder = [NSMutableArray new];
    while (!finish) {
        if (pthread_mutex_trylock(&_lock) == 0) {
            if (_lru->_totalCount > countLimit) {
                _LTLinkedMapNode *node = [self removeHeadOrTail];
                if (node) [holder addObject:node];
            } else {
                finish = YES;
            }
            pthread_mutex_unlock(&_lock);
        } else {
            usleep(10 * 1000); //10 ms
        }
    }

    if (holder.count) {
        dispatch_queue_t queue = _lru->_releaseOnMainThread ? dispatch_get_main_queue() : LTMemoryCacheGetReleaseQueue();
        dispatch_async(queue, ^{
            [holder count]; // release in queue
        });
    }
}

- (void)_trimToAge:(NSTimeInterval)ageLimit {
    BOOL finish = NO;
    NSTimeInterval now = CACurrentMediaTime();
    pthread_mutex_lock(&_lock);
    if (ageLimit <= 0) {
        [self removeAllList];
        finish = YES;
    } else if (!_lru->_tail || (now - _lru->_tail->_time) <= ageLimit)
    {
        finish = YES;
    }
    pthread_mutex_unlock(&_lock);
    if (finish) return;
    
    NSMutableArray *holder = [NSMutableArray new];
    while (!finish) {
        if (pthread_mutex_trylock(&_lock) == 0) {
           
            if (_lru->_tail && (now - _lru->_tail->_time) > ageLimit) {
                _LTLinkedMapNode *node = [self removeHeadOrTail];
                if (node) [holder addObject:node];
            } else {
                finish = YES;
            }
            pthread_mutex_unlock(&_lock);
        } else {
            usleep(10 * 1000);
        }
    }
    if (holder.count) {
        dispatch_queue_t queue = _lru->_releaseOnMainThread ? dispatch_get_main_queue() : LTMemoryCacheGetReleaseQueue();
        dispatch_async(queue, ^{
            [holder count];
        });
    }
}

- (void)_appDidReceiveMemoryWarningNotification {
    if (self.didReceiveMemoryWarningBlock) {
        self.didReceiveMemoryWarningBlock(self);
    }
    if (self.shouldRemoveAllObjectsOnMemoryWarning) {
        [self removeAllObjects];
    }
}

- (void)_appDidEnterBackgroundNotification {
    if (self.didEnterBackgroundBlock) {
        self.didEnterBackgroundBlock(self);
    }
    if (self.shouldRemoveAllObjectsWhenEnteringBackground) {
        [self removeAllObjects];
    }
}

#pragma mark - Init Method

- (instancetype)init {

    return [self initWithCache:LTCacheListTypeLRU];
}

- (instancetype)initWithCache:(LTCacheListType )type {
    self = [super init];
    
    pthread_mutex_init(&_lock, NULL);
    _lru = [_LTLinkedMap new];
    _lruGhost = [_LTLinkedMap new];
    _queue = dispatch_queue_create("com.cache.memory", DISPATCH_QUEUE_SERIAL);
    
//    _countLimit = NSUIntegerMax;
    _countLimit = NSUIntegerMax;
    _costLimit = NSUIntegerMax;
    _ageLimit = DBL_MAX;
    _autoTrimInterval = 5.0;
    _shouldRemoveAllObjectsOnMemoryWarning = YES;
    _shouldRemoveAllObjectsWhenEnteringBackground = YES;
    _type = type;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_appDidReceiveMemoryWarningNotification) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_appDidEnterBackgroundNotification) name:UIApplicationDidEnterBackgroundNotification object:nil];
    
    [self _trimRecursively];
    
    return self;
}


- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    [_lru removeAll];
    [_lruGhost removeAll];
    pthread_mutex_destroy(&_lock);
}

- (NSUInteger)totalCount {
    pthread_mutex_lock(&_lock);
    NSUInteger count = _lru->_totalCount;
    pthread_mutex_unlock(&_lock);
    return count;
}

- (NSUInteger)totalCost {
    pthread_mutex_lock(&_lock);
    NSUInteger totalCost = _lru->_totalCost;
    pthread_mutex_unlock(&_lock);
    return totalCost;
}

- (BOOL)releaseOnMainThread {
    pthread_mutex_lock(&_lock);
    BOOL releaseOnMainThread = _lru->_releaseOnMainThread;
    pthread_mutex_unlock(&_lock);
    return releaseOnMainThread;
}

- (void)setReleaseOnMainThread:(BOOL)releaseOnMainThread {
    pthread_mutex_lock(&_lock);
    _lru->_releaseOnMainThread = releaseOnMainThread;
    _lruGhost->_releaseOnMainThread = releaseOnMainThread;
    pthread_mutex_unlock(&_lock);
}

- (BOOL)releaseAsynchronously {
    pthread_mutex_lock(&_lock);
    BOOL releaseAsynchronously = _lru->_releaseAsynchronously;
    pthread_mutex_unlock(&_lock);
    return releaseAsynchronously;
}

- (void)setReleaseAsynchronously:(BOOL)releaseAsynchronously {
    pthread_mutex_lock(&_lock);
    _lru->_releaseAsynchronously = releaseAsynchronously;
    _lruGhost->_releaseAsynchronously = releaseAsynchronously;
    pthread_mutex_unlock(&_lock);
}

- (BOOL)containsObjectForKey:(id)key {
    if (!key) return NO;
    pthread_mutex_lock(&_lock);
    BOOL contains = CFDictionaryContainsKey(_lru->_dic, (__bridge const void *)(key));
    pthread_mutex_unlock(&_lock);
    return contains;
}

- (id)objectForKey:(id)key {
    if (!key) return nil;
    pthread_mutex_lock(&_lock);
    _LTLinkedMapNode *node = CFDictionaryGetValue(_lru->_dic, (__bridge const void *)(key));
    if (node) {
        node->_time = CACurrentMediaTime();
        [_lru bringNodeToHead:node];
    } else {
        node = CFDictionaryGetValue(_lruGhost->_dic, (__bridge const void *)(key));
        switch (_type) {
            case LTCacheListTypeLRUGhost :
                if (node) {
                    node->_time = CACurrentMediaTime();
                     [_lruGhost removeNode:node];
                    [_lru insertNodeAtHead:node];
                   
                }
                break;
            case LTCacheListTypeMRU :
            case LTCacheListTypeLRU :

                break;
            default:
                break;
        }
    }
    pthread_mutex_unlock(&_lock);
    return node ? node->_value : nil;
}

- (void)setObject:(id)object forKey:(id)key {
    
    [self setObject:object forKey:key withCost:0];
}

- (void)setObject:(id)object forKey:(id)key withCost:(NSUInteger)cost {
    if (!key) return;
    if (!object) {
        [self removeObjectForKey:key];
        return;
    }
    pthread_mutex_lock(&_lock);
    _LTLinkedMapNode *node = CFDictionaryGetValue(_lru->_dic, (__bridge const void *)(key));
    NSTimeInterval now = CACurrentMediaTime();
    if (node) {
        _lru->_totalCost -= node->_cost;
        _lru->_totalCost += cost;
        node->_cost = cost;
        node->_time = now;
        node->_value = object;
        [_lru bringNodeToHead:node];
    } else {
        node = CFDictionaryGetValue(_lruGhost->_dic, (__bridge const void *)(key));
        switch (_type) {
            case LTCacheListTypeLRUGhost :
                if (node) {
                    node->_time = CACurrentMediaTime();
                    [_lruGhost removeNode:node];
                    [_lru insertNodeAtHead:node];
                    
                } else {
                    node = [_LTLinkedMapNode new];
                    node->_cost = cost;
                    node->_time = now;
                    node->_key = key;
                    node->_value = object;
                    [_lru insertNodeAtHead:node];
                }
                break;
            case LTCacheListTypeMRU :
            case LTCacheListTypeLRU :
                node = [_LTLinkedMapNode new];
                node->_cost = cost;
                node->_time = now;
                node->_key = key;
                node->_value = object;
                [_lru insertNodeAtHead:node];
                break;
            default:
            break;
        }
    }
    switch (_type) {
        case LTCacheListTypeLRUGhost :
            [self setObjectLruOrLruGhost:_lru];
//            [self setObjectLruOrLruGhost:_lruGhost];
            break;
        case LTCacheListTypeMRU :
        case LTCacheListTypeLRU :
            [self setObjectLruOrLruGhost:_lru];
        default:
            break;
    }
    pthread_mutex_unlock(&_lock);
}

- (void)removeObjectForKey:(id)key {
    if (!key) return;
    pthread_mutex_lock(&_lock);
    _LTLinkedMapNode *node = CFDictionaryGetValue(_lru->_dic, (__bridge const void *)(key));
    if (node) {
        
        switch (_type) {
            case LTCacheListTypeLRUGhost:
                [_lru removeNode:node];
                [_lruGhost insertNodeAtHead:node];
               
                break;
                case LTCacheListTypeMRU:
                case LTCacheListTypeLRU:
                 [_lru removeNode:node];
                break;
            default:
                break;
        }
        
        
        if (_lru->_releaseAsynchronously) {
            dispatch_queue_t queue = _lru->_releaseOnMainThread ? dispatch_get_main_queue() : LTMemoryCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                [node class]; //hold and release in queue
            });
        } else if (_lru->_releaseOnMainThread && !pthread_main_np()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [node class]; //hold and release in queue
            });
        }
    }
    pthread_mutex_unlock(&_lock);
}

- (void)removeAllObjects {
    pthread_mutex_lock(&_lock);
    [_lru removeAll];
    [_lruGhost removeAll];
    pthread_mutex_unlock(&_lock);
}

- (void)trimToCount:(NSUInteger)count {
    if (count == 0) {
        [self removeAllObjects];
        return;
    }
    [self _trimToCount:count];
}

- (void)trimToCost:(NSUInteger)cost {
    [self _trimToCost:cost];
}

- (void)trimToAge:(NSTimeInterval)age {
    [self _trimToAge:age];
}

- (NSString *)description {
    if (_name) return [NSString stringWithFormat:@"<%@: %p> (%@)", self.class, self, _name];
    else return [NSString stringWithFormat:@"<%@: %p>", self.class, self];
}

@end

