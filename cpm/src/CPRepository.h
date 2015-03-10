//
//  CPRepository.h
//  cpm
//
//  Created by Alexander Zielenski on 3/2/15.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <FMDatabase.h>

@interface CPRepository : NSObject
@property (readonly, strong) NSURL *url;

@property (copy) NSString *label;
@property (copy) NSNumber *version;
@property (copy) NSString *architectures;
@property (copy) NSString *repoPescription;
@property (strong) FMDatabase *database;

+ (instancetype)repositoryWithURL:(NSURL *)url;
- (instancetype)initWithURL:(NSURL *)url;

- (void)reloadData:(void (^)(NSError *error))completion;

- (NSArray *)listPackages;
- (NSArray *)searchForPackage:(NSString *)query;
- (void)downloadPackage:(NSString *)identifier dependencies:(BOOL)deps completion:(void (^)(NSURL *url, NSError *err))completion;

@end

@interface CPRepository (Properties)
@property (readonly, strong) NSArray *packages;
@end
