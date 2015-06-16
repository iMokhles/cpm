//
//  CPMPackageManagerAggregate.m
//  
//
//  Created by Adam D on 15/06/2015.
//
//

#import "CPMPackageManagerAggregate.h"
#import "CPMHomebrewPackageManager.h"
#import "CPMDpkgPackageManager.h"

@implementation CPMPackageManagerAggregate {
	NSArray *_packageManagers;
}

+ (instancetype)sharedInstance {
	static CPMPackageManagerAggregate *sharedInstance;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedInstance = [[self alloc] init];
	});
	
	return sharedInstance;
}

- (instancetype)init {
	self = [super init];
	
	if (self) {
		_packageManagers = @[
			[[CPMHomebrewPackageManager alloc] init],
			[[CPMDpkgPackageManager alloc] init]
		];
	}
	
	return self;
}

- (NSArray *)installedPackages {
	NSMutableArray *packages = [NSMutableArray array];
	 
	for (id <CPMPackageManager> packageManager in _packageManagers) {
		[packages addObjectsFromArray:packageManager.installedPackages];
	}
	
	return packages;
}

- (void)refreshWithCompletion:(CPMPackageManagerRefreshCompletion)completion {
	completion(nil);
}

- (void)packagesForIdentifiers:(NSArray *)identifiers completion:(CPMPackageManagerPackagesForIdentifiersCompletion)completion {
	/*
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		for (id <CPMPackageManager> packageManager in _packageManagers) {
			// TODO: do something
		}
	});
	*/
	
	completion(nil, nil);
}

- (NSProgress *)package:(id <CPMPackage>)package performOperation:(CPMPackageManagerOperation)operation stateChangeCallback:(CPMPackageManagerStateChangeCallback)stateChangeCallback {
	// TODO: implement
	NSProgress *progress = [NSProgress progressWithTotalUnitCount:1];
	return progress;
}

@end
