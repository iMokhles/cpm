//
//  CPMHomebrewPackage.m
//  cpm
//
//  Created by Adam D on 10/06/2015.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//

#import "CPMHomebrewPackage.h"

@implementation CPMHomebrewPackage

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
	self = [self init];

	if (self) {
		[self updateWithDictionary:dictionary];
	}

	return self;
}

- (void)updateWithDictionary:(NSDictionary *)dictionary {
	// TODO: support compilation options

	BOOL installed = !!dictionary[@"installed"];

	_identifier = dictionary[@"full_name"];
	_name = dictionary[@"name"];

	_version = dictionary[@"versions"][@"stable"];

	if (((NSNumber *)dictionary[@"revision"]).integerValue > 0) {
		_version = [_version stringByAppendingFormat:@"-%@", (NSNumber *)dictionary[@"revision"]];
	}

	_state = installed ? CPMPackageStateInstalled : CPMPackageStateNone;
	_shortDescription = dictionary[@"desc"];

	_depends = dictionary[@"dependencies"];
	_conflicts = dictionary[@"conflicts_with"];

	_requiresCompilation = !dictionary[@"versions"][@"bottle"];
	_installationWarnings = [dictionary[@"caveats"] isKindOfClass:NSString.class] ? dictionary[@"caveats"] : nil;

	_installIsKegOnly = ((NSNumber *)dictionary[@"keg_only"]).boolValue;

	_websiteURL = dictionary[@"homepage"] ? [NSURL URLWithString:dictionary[@"homepage"]] : nil;
}

@end
