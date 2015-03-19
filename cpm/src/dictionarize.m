//
//  dictionarize.c
//  cpm
//
//  Created by Alexander Zielenski on 3/18/15.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//

#import "dictionarize.h"

static NSMutableDictionary *keyCache = nil;

NSString *keyForDB(FMDatabase *db, NSString *table) {
    return [NSString stringWithFormat:@"%@%@", db, table];
}

NSDictionary *dictionarize(NSString *data, FMDatabase *db, NSString *table) {
    if (!keyCache) {
        keyCache = [[NSMutableDictionary alloc] init];
    }
    NSMutableArray *validKeys = [NSMutableArray array];
    NSString *cacheKey = keyForDB(db, table);
    if ([keyCache.allKeys containsObject:cacheKey]) {
        validKeys = keyCache[cacheKey];
    } else {
        FMResultSet *results = [db executeQuery:[NSString stringWithFormat:@"PRAGMA table_info(%@)", table]];
        while (results.next) {
            [validKeys addObject:[results stringForColumn:@"name"].copy];
        }
        [results close];
        
        keyCache[cacheKey] = validKeys;
    }
    
    NSArray *components = [data componentsSeparatedByString:@"\n"];
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    
    NSString *lastKey = nil;
    for (NSString *segment in components) {
        NSRange keyRange = [segment rangeOfString:@":"];
        if (keyRange.location == NSNotFound) {
            // append it to the last one
            if (!lastKey)
                continue;
            
            NSString *lastValue = values[lastKey];
            if (!lastValue.length) {
                values[lastKey] = segment;
            } else {
                values[lastKey] = [lastValue stringByAppendingFormat:@"\n%@", segment];
            }
            
            continue;
        }
        
        NSString *key = [segment substringToIndex:keyRange.location].lowercaseString;
        key = [key stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
        if (![validKeys containsObject:key]) {
            continue;
        }
        
        NSString *value = [segment substringFromIndex:keyRange.location + keyRange.length];
        value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        values[key] = value;
        lastKey = key;
    }
    
    return values;
}
