//
//  main.m
//  cpm
//
//  Created by Alexander Zielenski on 3/2/15.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <bzlib.h>
#include <zlib.h>
#import "CPMDpkgRepositoryAggregate.h"

//https://wiki.debian.org/RepositoryFormat#Types_of_files
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSArray *sources = @[
                             [NSURL URLWithString:@"http://repo.alexzielenski.com"],
                             [NSURL URLWithString:@"http://apt.thebigboss.org/repofiles/cydia"],
                             [NSURL URLWithString:@"http://cydia.zodttd.com/repo/cydia"],
                             [NSURL URLWithString:@"http://apt.modmyi.com"]
                             ];
        
        
        CPMDpkgRepositoryAggregate *aggregate = [[CPMDpkgRepositoryAggregate alloc] initWithRepositoryURLs:sources];
        [aggregate reloadDataWithCompletion:^(CPMRepository *finished, NSError *error, BOOL allFinished) {
            NSLog(@"Finished Loading: %@ with error: %@", finished.url, error);
            if (allFinished) {
                NSLog(@"done loading all repos");
                
                NSLog(@"%@", [aggregate.repositories valueForKeyPath:@"label"]);
                NSLog(@"%@", [aggregate packageWithIdentifier:@"com.alexzielenski.zeppelin"]);
            }
        }];

        [[NSRunLoop currentRunLoop] run];
        
    }
    return 0;
}
