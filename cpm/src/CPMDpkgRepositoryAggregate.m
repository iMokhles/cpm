//
//  CPMRepositoryAggregate.m
//  cpm
//
//  Created by Alexander Zielenski on 3/8/15.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//

#import "CPMDpkgRepositoryAggregate.h"

@interface CPMDpkgRepositoryAggregate ()
@property (readwrite, strong) NSMutableSet *repositories;
@end

@implementation CPMDpkgRepositoryAggregate

+ (instancetype)aggregateWithRepositoryURLs:(NSArray *)urls {
    return [[self alloc] initWithRepositoryURLs:urls];
}

- (instancetype)initWithRepositoryURLs:(NSArray *)urls {
    if ((self = [self init])) {
        self.repositories = [NSMutableSet set];
        for (NSURL *url in urls) {
            CPMRepository *repo = [CPMRepository repositoryWithURL:url];
            if (repo)
                [self.repositories addObject:repo];
        }
    }
    
    return self;
}

- (CPMRepository *)repositoryWithURL:(NSURL *)url {
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"url == %@", url];
    NSSet *filter = [self.repositories filteredSetUsingPredicate:pred];
    return filter.anyObject;
}

- (void)reloadDataWithCompletion:(void (^)(CPMRepository *repo, NSError *error, BOOL allFinished))completion {
    __weak CPMDpkgRepositoryAggregate *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block NSUInteger finishedRepos = 0;
        __block NSUInteger allRepos      = weakSelf.repositories.count;
        
        for (CPMRepository *repo in weakSelf.repositories) {
            [repo reloadData:^(NSError *error) {
                finishedRepos++;
                completion(repo, error, finishedRepos == allRepos);
            }];
        }
    });
}

- (void)installPackage:(NSString *)identifier {
    NSDictionary *package = [self packageWithIdentifier:identifier];
    NSLog(@"%@", package);
}

- (void)downloadPackageWithIdentifier:(NSString *)identifier dependencies:(BOOL)deps completion:(void (^)(NSURL *path, NSError *error))completion {
    //!TODO: interface with dpkg and shrink the deps list down to dependencies which have not been installed
    //! also, do proper version checking
}

- (NSDictionary *)packageWithIdentifier:(NSString *)identifier {
    NSDictionary *package = nil;
    
    for (CPMRepository *repo in self.repositories) {
        if ((package = [repo packageWithIdentifier:identifier]))
            break;
    }
    
    return package;
}

- (NSArray *)searchForPackage:(NSString *)query {
    NSMutableArray *packages = [NSMutableArray array];
    
    for (CPMRepository *repo in self.repositories) {
        [packages addObjectsFromArray:[repo searchForPackage:query]];
    }
    
    return packages;
}

- (NSSet *)groupNames {
    NSMutableSet *aggregate = [NSMutableSet set];
    for (CPMRepository *repo in self.repositories) {
        [aggregate addObjectsFromArray:repo.groupNames.allObjects];
    }
    
    return aggregate;
}

- (NSArray *)packagesInGroup:(NSString *)group {
    NSMutableArray *aggregate = [NSMutableArray array];
    for (CPMRepository *repo in self.repositories) {
        [aggregate addObjectsFromArray:[repo packagesInGroup:group]];
    }
    
    return aggregate;
}

@end
