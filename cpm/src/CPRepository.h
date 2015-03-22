//
//  CPRepository.h
//  cpm
//
//  Created by Alexander Zielenski on 3/2/15.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <FMDatabaseQueue.h>
#import <FMDatabase.h>

@interface CPRepository : NSObject
@property (readonly, strong) NSURL *url;

@property (copy) NSString *label;
@property (copy) NSNumber *version;
@property (copy) NSString *architectures;
@property (copy) NSString *repoDescription;
@property (strong) FMDatabaseQueue *databaseQueue;
@property (readonly, copy) NSURL *binaryBaseURL;

+ (instancetype)repositoryWithURL:(NSURL *)url;
- (instancetype)initWithURL:(NSURL *)url;

- (void)reloadData:(void (^)(NSError *error))completion;

- (NSArray *)listPackages;
- (NSArray *)searchForPackage:(NSString *)query;
- (NSDictionary *)packageWithIdentifier:(NSString *)identifier;

- (NSSet *)groupNames;
- (NSArray *)packagesInGroup:(NSString *)group;

@end

@interface CPRepository (Properties)
@property (readonly, strong) NSArray *packages;
@end
