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
#import "CPRepository.h"

//https://wiki.debian.org/RepositoryFormat#Types_of_files
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSArray *sources = @[
                             [NSURL URLWithString:@"http://repo.alexzielenski.com"]
                             ];
        
        NSMutableArray *repos = [NSMutableArray array];
        // insert code here...
        for (NSURL *source in sources) {
            [repos addObject:[CPRepository repositoryWithURL:source]];
        }
        
        [repos makeObjectsPerformSelector:@selector(reloadData)];
//        [repos makeObjectsPerformSelector:@selector(listPackages)];
        [[NSRunLoop currentRunLoop] run];
        
    }
    return 0;
}
