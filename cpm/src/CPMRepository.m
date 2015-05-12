//
//  CPMRepository.m
//  cpm
//
//  Created by Alexander Zielenski on 3/2/15.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//
// https://wiki.debian.org/RepositoryFormat#Types_of_files

#import "CPMRepository.h"
#import "CPDefines.h"
#import "CPMCurler.h"
#import "decompress.h"
#import "dictionarize.h"

typedef NS_ENUM(NSUInteger, CPMRepositoryIndexCompression) {
    CPMRepositoryIndexCompressionLZMA,
    CPMRepositoryIndexCompressionXZ,
    CPMRepositoryIndexCompressionLZIP,
    CPMRepositoryIndexCompressionBzip2,
    CPMRepositoryIndexCompressionGzip2,
    CPMRepositoryIndexCompressionNone
};

typedef NS_ENUM(NSUInteger, CPMRepositoryFormat) {
    CPMRepositoryFormatFlat = 0,
    CPMRepositoryFormatModern = 1
};

typedef NS_ENUM(NSUInteger, CPMRepositoryIndex) {
    CPMRepositoryIndexRelease = 0,
    CPMRepositoryIndexPackages = 1,
    CPMRepositoryIndexSources = 2
};

NSString *extensionForCompression(CPMRepositoryIndexCompression compression) {
    switch (compression) {
        case CPMRepositoryIndexCompressionBzip2:
            return @"bz2";
        case CPMRepositoryIndexCompressionGzip2:
            return @"gz";
        case CPMRepositoryIndexCompressionLZMA:
            return @"lzma";
        case CPMRepositoryIndexCompressionLZIP:
            return @"lz";
        case CPMRepositoryIndexCompressionXZ:
            return @"xz";
        case CPMRepositoryIndexCompressionNone:
        default:
            return @"";
    }
    
    return @"";
}

//!TODO: remove any user/pass authentication in the URL
NSString *baseify(NSURL *url) {
    NSString *scheme = url.scheme;
    NSString *substr = [url.absoluteString substringFromIndex:scheme.length + 3]; /* :// */
    return [[substr stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByReplacingOccurrencesOfString:@":" withString:@"@"];
}

NSString *argumentsForUpdateDictionary(NSDictionary *dict) {
    // returns in the format (keys) values (:values)
    return [NSString stringWithFormat:@"(%@) values (:%@)", [dict.allKeys componentsJoinedByString:@", "], [dict.allKeys componentsJoinedByString:@", :"]];
}

@interface CPMRepository ()
@property (readwrite, strong) NSURL *url;
@property (strong) NSMutableData *releaseData;
@property (strong) NSMutableData *sourcesData;
@property (strong) NSOperationQueue *downloadQueue;
@property (assign) CPMRepositoryFormat format;
@property (readwrite, copy) NSURL *binaryBaseURL;
@property (copy) void (^reloadCompletion)(NSError *);
- (void)obtainIndices;
- (void)obtainReleaseIndexWithCompression:(CPMRepositoryIndexCompression)compression;
- (void)updateRepositoryInformationFromDatabase:(FMDatabase *)db;
- (NSDictionary *)packageWithResultSet:(FMResultSet *)result;
@end

@implementation CPMRepository

+ (instancetype)repositoryWithURL:(NSURL *)url {
    return [[self alloc] initWithURL:url];
}

- (instancetype)initWithURL:(NSURL *)url {
    if ((self = [super init])) {
        self.downloadQueue = [[NSOperationQueue alloc] init];
        self.url = url;
        
        [[NSFileManager defaultManager] createDirectoryAtPath:LOCALSTORAGE_PATH
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        
        // Generate database path for this url:
        NSString *dbPath = [LOCALSTORAGE_PATH stringByAppendingPathComponent:baseify(self.url)];
        self.databaseQueue = [FMDatabaseQueue databaseQueueWithPath:dbPath];
        
        if (!self.databaseQueue) {
            //!TODO: error
            NSLog(@"couldnt open database for writing");
            return nil;
        }
        
        [self.databaseQueue inDatabase:^(FMDatabase *db) {
            db.shouldCacheStatements = NO;
            [self updateRepositoryInformationFromDatabase:db];
        }];
    }
    
    return self;
}

- (void)reloadData:(void (^)(NSError *error))completion; {
    __weak CPMRepository *weakSelf = self;
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:@"drop table if exists release"];
        [db executeUpdate:@"create table release (architectures text, codename text, components text, description text, label text, suite text, version text, origin text, md5sum text, sha1 text, sha256 text)"];
        [db executeUpdate:@"create table if not exists packages (package text primary key, size integer, version text, filename text, architecture text, maintainer text, installed_size integer, depends text, md5sum text, sha1 text, sha256 text, section text, priority text, homepage text, description text, author text, depiction text, sponsor text, icon text, name text)"];
        
        weakSelf.reloadCompletion = completion;
        [weakSelf obtainIndices];
    }];
}

- (void)dealloc {
    [self.databaseQueue close];
}

#pragma mark - Network Operations

// Release, Packages, Sources
//!TODO: Implement HTTP authentication or make the user put it into the url
- (void)obtainIndices {
    [self obtainReleaseIndexWithCompression:CPMRepositoryIndexCompressionNone];
}

//!TODO: utilize FMDB's database queue for multitheading
- (void)obtainPackagesIndexWithCompression:(CPMRepositoryIndexCompression)compression {
    if (compression > CPMRepositoryIndexCompressionNone) {
        // error...
        return;
    }
    
    // find the appropriate url for the packages index
    NSURL *packagesURL = [self urlForIndex:CPMRepositoryIndexPackages withFormat:self.format];
    
    // append correct extension for compression
    NSString *ext = extensionForCompression(compression);
    if (ext.length > 0) {
        packagesURL = [packagesURL URLByAppendingPathExtension:ext];
    }
    
    __weak CPMRepository *weakSelf = self;
    NSLog(@"%@", packagesURL);
    
    // attempt to download the packages index
    CPMCurler *curl = [[CPMCurler alloc] initWithURL:packagesURL
                                           dataBlock:^(NSInteger bytesDownloaded, NSInteger bytesExpected, NSData *data) {
                                               //!TODO do something with progress
                                           }
                                     completionBlock:nil];
    __weak CPMCurler *weakCurl = curl;
    curl.completionBlock = ^{
        if (weakCurl.error) {
            // we couldn't pull them down, so try a different compression extension.
            // the beginning of this method has an end condition to prevent stack overflow
            if (weakCurl.error.code == CPMErrorUnacceptableStatusCode) {
                [weakSelf obtainPackagesIndexWithCompression:compression + 1];
            }
        } else {
            @autoreleasepool {
                dispatch_async(dispatch_get_global_queue(0, DISPATCH_QUEUE_PRIORITY_HIGH), ^{
                    NSString *package = decompress(weakCurl.data);
                    if (!package) {
                        if (weakSelf.reloadCompletion) {
                            //!TODO: localize this
                            dispatch_async(dispatch_get_main_queue(), ^{
                                weakSelf.reloadCompletion([NSError errorWithDomain:CPMERRORDOMAIN code:CPMErrorDecompression userInfo:@{
                                                                                                                                        NSLocalizedFailureReasonErrorKey: @"The downloaded packages index was in an unrecognizable format and could not be decompressed"
                                                                                                                                        }]);
                            });
                            weakSelf.reloadCompletion = nil;
                        }
                        NSLog(@"could not decompress package data");
                        return;
                    }
                    
                    
                    [weakSelf.databaseQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
                        BOOL succ = YES;
                        
                        NSRange range = NSMakeRange(0, package.length);
                        while (range.location != NSNotFound) {
                            @autoreleasepool {
                                if (!succ) {
                                    if (weakSelf.reloadCompletion) {
                                        weakSelf.reloadCompletion([NSError errorWithDomain:CPMERRORDOMAIN
                                                                                  code:CPMErrorDatabase
                                                                              userInfo:@{
                                                                                         @"code": @(db.lastErrorCode),
                                                                                         NSLocalizedDescriptionKey: @"Failed to commit changes to database, rolling back...",
                                                                                         NSLocalizedFailureReasonErrorKey: db.lastErrorMessage
                                                                                         }]);
                                        weakSelf.reloadCompletion = nil;
                                    }
                                    NSLog(@"%@", db.lastErrorMessage);
                                    *rollback = YES;
                                    break;
                                }
                                
                                // find the next paragraph, each is separated by a newline
                                NSRange nextRange = [package rangeOfString:@"\n\n"
                                                                   options:NSLiteralSearch
                                                                     range:NSMakeRange(range.location + 2, package.length - range.location - 2)];
                                NSUInteger end = nextRange.location;
                                if (end == NSNotFound) {
                                    end = package.length;
                                }
                                
                                // retreive the string for the whole paragraph
                                NSString *segment = [package substringWithRange:NSMakeRange(range.location, end - range.location)];
                                range = nextRange;
                                
                                // parse the values into a dictionary
                                NSDictionary *dict = dictionarize(segment, db, @"packages");
                                if (dict.count == 0) {
                                    continue;
                                }
                                
                                // update the database value
                                NSString *query = [NSString stringWithFormat:@"insert or replace into packages %@",
                                                   argumentsForUpdateDictionary(dict)];
                                succ = [db executeUpdate:query withParameterDictionary:dict];
                            } //autoreleasepool
                            
                        } // while loop
                        
                        if (succ) {
                            if (weakSelf.reloadCompletion) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    weakSelf.reloadCompletion(nil);
                                });
                            }
                        }
                    }]; // inTransaction
                    
                    
                }); //dispatch_async
            } // autoreleasepool
        } // else
    }; // dispatch_async
    
    [self.downloadQueue addOperation:curl];
}

- (void)obtainReleaseIndexWithCompression:(CPMRepositoryIndexCompression)compression {
    if (compression > CPMRepositoryIndexCompressionNone) {
        if (self.format < CPMRepositoryFormatModern) {
            self.format++;
            [self obtainReleaseIndexWithCompression:0];
            return;
        }
        // error...
        return;
    }
    
    NSURL *releaseURL = [self urlForIndex:CPMRepositoryIndexRelease
                               withFormat:self.format];
    NSString *ext = extensionForCompression(compression);
    if (ext.length > 0) {
        releaseURL = [releaseURL URLByAppendingPathExtension:ext];
    }
    
    __weak CPMRepository *weakSelf = self;
    [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:releaseURL
                                                              cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                          timeoutInterval:5]
                                       queue:self.downloadQueue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                               // if we could not find the file, progress through each supported compression format until we get a match
                               NSLog(@"%@", releaseURL);
                               if (connectionError || ((NSHTTPURLResponse *)response).statusCode != 200) {
                                   return [weakSelf obtainReleaseIndexWithCompression:compression + 1];
                               } else if (data) {
                                   NSString *strRep = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                                   [weakSelf.databaseQueue inDatabase:^(FMDatabase *db) {
                                       NSDictionary *information = dictionarize(strRep, db, @"release");
                                       NSString *format = [NSString stringWithFormat:@"insert into release %@", argumentsForUpdateDictionary(information)];
                                       [db executeUpdate:format withParameterDictionary:information];
                                   }];
                                   
                                   [weakSelf.databaseQueue inDatabase:^(FMDatabase *db) {
                                       [weakSelf updateRepositoryInformationFromDatabase:db];
                                   }];
                                   
                                   [weakSelf obtainPackagesIndexWithCompression:CPMRepositoryIndexCompressionLZMA];
                               }
                           }];
}

- (void)updateRepositoryInformationFromDatabase:(FMDatabase *)db {
    FMResultSet *results = [db executeQuery:@"select * from release limit 1"];
    [results next];
    self.label = [results stringForColumn:@"label"];
    self.repoDescription = [results stringForColumn:@"description"];
    self.version = @([results doubleForColumn:@"version"]);
    self.architectures = [results stringForColumn:@"architectures"];
    
    [results close];
}

#pragma mark - API

- (NSArray *)listPackages {
    __block NSMutableArray *list = [NSMutableArray array];
    
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *results = [db executeQuery:@"select package, name, description, icon, version, section from packages"];
        while ([results next]) {
            [list addObject:[self packageWithResultSet:results]];
        }
        
        [results close];
    }];
    
    return list;
}

- (NSArray *)searchForPackage:(NSString *)input {
    __block NSMutableArray *list = [NSMutableArray array];
    
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        NSString *query = [NSString stringWithFormat:@"select * from packages where name like '%%%@%%'", input];
        FMResultSet *results = [db executeQuery:query];
        while ([results next]) {
            [list addObject:[self packageWithResultSet:results]];
        }
        
        [results close];
        
    }];
    
    return list;
}

- (NSDictionary *)packageWithIdentifier:(NSString *)identifier {
    __block NSDictionary *dict = [NSMutableDictionary dictionary];
    
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        NSString *query = [NSString stringWithFormat:@"select * from packages where package is '%@' limit 2", identifier];
        FMResultSet *results = [db executeQuery:query];

        [results next];
        
        dict = [self packageWithResultSet:results];
        
        [results next];
        if (results.hasAnotherRow) {
            NSLog(@"too many items with the same identifier");
            dict = nil;
        }
        [results close];
    }];
    
    return dict.count > 0 ? dict : nil;
}

- (NSSet *)groupNames {
    __block NSSet *groups = nil;
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *result = [db executeQuery:@"select distinct section from packages"];
        NSDictionary *results = result.resultDictionary;
        if (results.count)
            groups = [NSSet setWithArray:(NSArray *)results[@"section"]];
        else
            groups = [NSSet set];
    }];
    
    return groups;
}

- (NSArray *)packagesInGroup:(NSString *)group {
    __block NSMutableArray *packages = [NSMutableArray array];
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *results = [db executeQueryWithFormat:@"select * in packages where section is '%@'", group];
        while (results.next) {
            [packages addObject:[self packageWithResultSet:results]];
        }
    }];
    
    return packages;
}

#pragma mark - Helpers

- (NSDictionary *)packageWithResultSet:(FMResultSet *)results {
    NSDictionary *map = results.columnNameToIndexMap;

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (NSString *key in map) {
        id value = [results objectForColumnName:key];
        if (value && ![value isKindOfClass:[NSNull class]]) {
            dict[key] = value;
        }
    }
    
    dict[@"repo"] = self.url;
    
    return dict;
}

- (NSURL *)urlForIndex:(CPMRepositoryIndex)index withFormat:(CPMRepositoryFormat)format {
    NSString *components = @"";
    switch (format) {
        case CPMRepositoryFormatFlat:
            switch (index) {
                case CPMRepositoryIndexRelease:
                    components = @"Release";
                    break;
                case CPMRepositoryIndexPackages:
                    components = @"Packages";
                    break;
                case CPMRepositoryIndexSources:
                    components = @"Sources";
                    break;
                default:
                    break;
            }
            break;
        case CPMRepositoryFormatModern:
            switch (index) {
                case CPMRepositoryIndexRelease:
                    components = @"dists/stable/Release";
                    break;
                case CPMRepositoryIndexPackages: {
                    __block NSString *comps = nil;
                    [self.databaseQueue inDatabase:^(FMDatabase *db) {
                        FMResultSet *results = [db executeQuery:@"select components from release limit 1"];
                        // use the first component from the release index
                        // if none specific, default to main
                        NSString *component = @"main";
                        if (results.next) {
                            NSString *res = [results stringForColumn:@"components"];
                            NSArray *separated = [res componentsSeparatedByString:@" "];
                            if (separated.count)
                                comps = separated[0];
                        }
                        //!TODO: make sure architectures matches what we want somewhere, and if not, error out
                        comps = [NSString stringWithFormat:@"dists/stable/%@/binary-iphoneos-arm/Packages", component];
                        
                        [results close];
                    }];
                    
                    components = comps;
                    break;
                }
                case CPMRepositoryIndexSources:
                    components = @"dists/stable/main/binary-iphoneos-arm/Sources";
                    break;
                default:
                    break;
            }
            break;
        default:
            break;
    }
    
    return [self.url URLByAppendingPathComponent:components];
}

@end
