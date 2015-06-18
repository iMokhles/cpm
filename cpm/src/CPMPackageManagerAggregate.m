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

- (NSProgress *)refreshWithCompletion:(CPMPackageManagerAggregateRefreshCompletion)completion {
	dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	NSProgress *progress = [NSProgress progressWithTotalUnitCount:_packageManagers.count * 100];
	
	dispatch_async(queue, ^{
		NSMutableArray *errors = [NSMutableArray array];
		
		for (id <CPMPackageManager> packageManager in _packageManagers) {
			dispatch_async(queue, ^{
				[progress becomeCurrentWithPendingUnitCount:100];
				
				[packageManager refreshWithParentProgress:progress completion:^(NSError *error) {
					if (error) {
						[errors addObject:error];
					}
					
					if (progress.fractionCompleted == 1) {
						completion(errors);
					}
				}];
				
				[progress resignCurrent];
			});
		}
	});
	
	return progress;
}

- (void)packagesForIdentifiers:(NSArray *)identifiers completion:(CPMPackageManagerPackagesForIdentifiersCompletion)completion {
	dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	dispatch_async(queue, ^{
		dispatch_group_t group = dispatch_group_create();
		
		NSMutableArray *errors = [NSMutableArray array];
		NSMutableDictionary *finalPackages = [NSMutableDictionary dictionary];
		
		for (id <CPMPackageManager> packageManager in _packageManagers) {
			dispatch_group_async(group, queue, ^{
				[packageManager packagesForIdentifiers:identifiers completion:^(NSDictionary *packages, NSError *error) {
					if (error) {
						[errors addObject:error];
						return;
					}
					
					[finalPackages addEntriesFromDictionary:packages];
				}];
			});
		}
		
		dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
		
		dispatch_async(dispatch_get_main_queue(), ^{
			NSError *error = nil;
			
			if (errors.count == 1) {
				error = errors[0];
			} else if (errors.count > 1) {
				// TODO: how should we report multiple errors?
				error = errors[0];
			}
			
			completion(finalPackages, error);
		});
	});
}

- (NSProgress *)package:(id <CPMPackage>)package performOperation:(CPMPackageManagerOperation)operation stateChangeCallback:(CPMPackageManagerStateChangeCallback)stateChangeCallback {
	return [[package.class packageManagerClass] package:package performOperation:operation stateChangeCallback:stateChangeCallback];
}

@end
