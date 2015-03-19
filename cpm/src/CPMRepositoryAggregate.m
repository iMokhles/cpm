//
//  CPMRepositoryAggregate.m
//  cpm
//
//  Created by Alexander Zielenski on 3/8/15.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//

#import "CPMRepositoryAggregate.h"

@interface CPMRepositoryAggregate ()
@property (readwrite, strong) NSMutableSet *repositories;
@end

@implementation CPMRepositoryAggregate

- (id)initWithRepositoryURLs:(NSArray *)urls {
    if ((self = [self init])) {
        self.repositories = [NSMutableSet set];
        for (NSURL *url in urls) {
            CPRepository *repo = [CPRepository repositoryWithURL:url];
            if (repo)
                [self.repositories addObject:repo];
        }
    }
    
    return self;
}

- (void)reloadDataWithCompletion:(void (^)(CPRepository *repo, NSError *error, BOOL allFinished))completion {
    __weak CPMRepositoryAggregate *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block NSUInteger finishedRepos = 0;
        __block NSUInteger allRepos      = weakSelf.repositories.count;
        
        for (CPRepository *repo in weakSelf.repositories) {
            [repo reloadData:^(NSError *error) {
                finishedRepos++;
                completion(repo, error, finishedRepos == allRepos);
            }];
        }
    });
}

- (void)downloadPackageWithIdentifier:(NSString *)identifier dependencies:(BOOL)deps completion:(void (^)(NSURL *path, NSError *error))completion {
    //!TODO: interface with dpkg and shrink the deps list down to dependencies which have not been installed
    //! also, do proper version checking
}

- (NSDictionary *)packageWithIdentifier:(NSString *)identifier {
    NSDictionary *package = nil;
    
    for (CPRepository *repo in self.repositories) {
        if ((package = [repo packageWithIdentifier:identifier]))
            break;
    }
    
    return package;
}

- (NSArray *)searchForPackage:(NSString *)query {
    // first key is the identifier and second is a dictionary containing its control paragraph information
    NSMutableArray *packages = [NSMutableArray array];
    
    for (CPRepository *repo in self.repositories) {
        [packages addObjectsFromArray:[repo searchForPackage:query]];
    }
    
    return packages;
}

@end
