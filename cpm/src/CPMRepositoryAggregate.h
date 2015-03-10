//
//  CPMRepositoryAggregate.h
//  cpm
//
//  Created by Alexander Zielenski on 3/8/15.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CPRepository.h"

@interface CPMRepositoryAggregate : NSObject
@end

@interface CPMRepositoryAggregate (Properties)
@property (readonly, strong) NSSet *repositories;

- (id)initWithRepositoryURLs:(NSArray *)urls;

// the completion handler is called multiple times with the repository that had just finished reloading
// the allFinished flag is set to true when all have been reloaded
- (void)reloadDataWithCompletion:(void (^)(CPRepository *finished, NSError *error, BOOL allFinished))completion;

- (void)downloadPackageWithIdentifier:(NSString *)identifier dependencies:(BOOL)deps completion:(void (^)(NSURL *path, NSError *error))completion;
- (NSDictionary *)packageWithIdentifier:(NSString *)identifier;
- (NSDictionary *)searchForPackage:(NSString *)query;

@end
