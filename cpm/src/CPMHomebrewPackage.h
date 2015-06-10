//
//  CPMHomebrewPackage.h
//  cpm
//
//  Created by Adam D on 10/06/2015.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CPMPackage.h"

@interface CPMHomebrewPackage : NSObject <CPMPackage>

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;

@property (strong, nonatomic) NSString *identifier;
@property (strong, nonatomic) NSString *name;
@property (strong, nonatomic) NSString *version;
@property (strong, nonatomic) NSString *installedVersion;
@property CPMPackageState state;
@property (strong, nonatomic) NSString *architecture;
@property (strong, nonatomic) NSString *maintainerName;
@property (strong, nonatomic) NSString *maintainerEmailAddress;
@property (strong, nonatomic) NSString *section;
@property (strong, nonatomic) NSString *shortDescription;
@property (strong, nonatomic) NSURL *downloadURL;
@property (strong, nonatomic) NSDictionary *rawFields;

@property (strong, nonatomic) NSArray *depends;
@property (strong, nonatomic) NSArray *preDepends;
@property (strong, nonatomic) NSArray *recommends;
@property (strong, nonatomic) NSArray *suggests;
@property (strong, nonatomic) NSArray *enhances;
@property (strong, nonatomic) NSArray *breaks;
@property (strong, nonatomic) NSArray *conflicts;
@property (strong, nonatomic) NSArray *provides;
@property (strong, nonatomic) NSArray *replaces;

@property (strong, nonatomic) NSString *longDescription;
@property (strong, nonatomic) NSString *authorName;
@property (strong, nonatomic) NSString *authorEmailAddress;
@property (strong, nonatomic) NSString *uploaderName;
@property (strong, nonatomic) NSString *uploaderEmailAddress;
@property BOOL requiresCompilation;
@property (strong, nonatomic) NSString *installationWarnings;
@property BOOL installIsKegOnly;

@property (strong, nonatomic) NSURL *websiteURL;
@property (strong, nonatomic) NSURL *supportURL;
@property (strong, nonatomic) NSURL *depictionURL;

@end
