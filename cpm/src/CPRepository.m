//
//  CPRepository.m
//  cpm
//
//  Created by Alexander Zielenski on 3/2/15.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//
// https://wiki.debian.org/RepositoryFormat#Types_of_files

#import "CPRepository.h"
#import "CPDefines.h"
#import "CPMCurler.h"
#import <archive.h>
#import <archive_entry.h>

typedef NS_ENUM(NSUInteger, CPRepositoryIndexCompression) {
    CPRepositoryIndexCompressionLZMA,
    CPRepositoryIndexCompressionXZ,
    CPRepositoryIndexCompressionLZIP,
    CPRepositoryIndexCompressionBzip2,
    CPRepositoryIndexCompressionGzip2,
    CPRepositoryIndexCompressionNone
};

typedef NS_ENUM(NSUInteger, CPRepositoryFormat) {
    CPRepositoryFormatFlat = 0,
    CPRepositoryFormatModern = 1
};

typedef NS_ENUM(NSUInteger, CPRepositoryIndex) {
    CPRepositoryIndexRelease = 0,
    CPRepositoryIndexPackages = 1,
    CPRepositoryIndexSources = 2
};

NSString *extensionForCompression(CPRepositoryIndexCompression compression) {
    switch (compression) {
        case CPRepositoryIndexCompressionBzip2:
            return @"bz2";
        case CPRepositoryIndexCompressionGzip2:
            return @"gz";
        case CPRepositoryIndexCompressionLZMA:
            return @"lzma";
        case CPRepositoryIndexCompressionLZIP:
            return @"lz";
        case CPRepositoryIndexCompressionXZ:
            return @"xz";
        case CPRepositoryIndexCompressionNone:
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

NSDictionary *dictionarize(NSString *data) {
    //!TODO: get these keys dynamically from the db columns
    NSArray *validKeys = @[
                           @"architectures",
                           @"codename",
                           @"components",
                           @"label",
                           @"suite",
                           @"origin",
                           @"package",
                           @"size", @"version", @"filename", @"architecture", @"maintainer", @"installed_size", @"depends", @"md5sum", @"sha1", @"sha256", @"section", @"priority", @"homepage", @"description", @"author", @"depiction", @"sponsor", @"icon", @"name"];
    NSArray *components = [data componentsSeparatedByString:@"\n"];
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    
    for (NSString *segment in components) {
        NSRange keyRange = [segment rangeOfString:@":"];
        if (keyRange.location == NSNotFound) {
            continue;
        }
        
        NSString *key = [segment substringToIndex:keyRange.location].lowercaseString;
        key = [key stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
        if (![validKeys containsObject:key]) {
            continue;
        }
        
        NSString *value = [segment substringFromIndex:keyRange.location + keyRange.length];
        value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        values[key] = value;
    }
    
    return values;
}

NSString *argumentsForUpdateDictionary(NSDictionary *dict) {
    // returns in the format (keys) values (:values)
    return [NSString stringWithFormat:@"(%@) values (:%@)", [dict.allKeys componentsJoinedByString:@", "], [dict.allKeys componentsJoinedByString:@", :"]];
}

NSString *decompress(NSData *data) {
    int r;
    ssize_t size;
    
    struct archive *a = archive_read_new();
    struct archive_entry *ae;
    archive_read_support_compression_all(a);
    archive_read_support_format_raw(a);
    r = archive_read_open_memory(a, (void *)data.bytes, data.length);
    
    NSMutableData *buffer = [[NSMutableData alloc] initWithLength:4096];
    
    if (r != ARCHIVE_OK) {
        /* ERROR */
        return @"";
    }
    r = archive_read_next_header(a, &ae);
    if (r != ARCHIVE_OK) {
        /* ERROR */
        return @"";
    }
    
    ssize_t bytesWritten = 0;
    NSMutableData *output = [[NSMutableData alloc] init];
    for (;;) {
        // read the next few mb of data
        size = archive_read_data(a, (void *)buffer.mutableBytes, 4096);
        if (size < 0) {
            /* ERROR */
        }
        if (size == 0)
            break;
        
        bytesWritten += size;
        [output appendData:buffer];
        [buffer resetBytesInRange:NSMakeRange(0, buffer.length)];
    }
    
    archive_read_free(a);
    
    return [[NSString alloc] initWithData:output encoding:NSASCIIStringEncoding];
}

@interface CPRepository ()
@property (readwrite, strong) NSURL *url;
@property (strong) NSMutableData *releaseData;
@property (strong) NSMutableData *sourcesData;
@property (strong) NSOperationQueue *downloadQueue;
@property (assign) CPRepositoryFormat format;
@property (readwrite, strong) NSMutableArray *packages;
@property (copy) void (^reloadCompletion)(NSError *);
- (void)obtainIndices;
- (void)obtainReleaseIndexWithCompression:(CPRepositoryIndexCompression)compression;
- (void)updateRepositoryInformationFromDatabase:(FMDatabase *)db;
@end

@implementation CPRepository

+ (instancetype)repositoryWithURL:(NSURL *)url {
    return [[self alloc] initWithURL:url];
}

- (instancetype)initWithURL:(NSURL *)url {
    if ((self = [super init])) {
        self.downloadQueue = [[NSOperationQueue alloc] init];
        self.url = url;
        self.packages = [NSMutableArray array];
        
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
            [self updateRepositoryInformationFromDatabase:db];
        }];
    }
    
    return self;
}

- (void)reloadData:(void (^)(NSError *error))completion; {
    __weak CPRepository *weakSelf = self;
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:@"drop table if exists release"];
        [db executeUpdate:@"create table release (architectures text, codename text, components text, description text, label text, suite text, version text, origin text)"];
        [db executeUpdate:@"create table if not exists packages (package text primary key, size integer, version text, filename text, architecture text, maintainer text, installed_size integer, depends text, md5sum text, sha1 text, sha256 text, section text, priority text, homepage text, description text, author text, depiction text, sponsor text, icon text, name text)"];
        
        weakSelf.reloadCompletion = completion;
        [weakSelf obtainIndices];
    }];
}

- (void)dealloc {
    [self.databaseQueue close];
}

// Release, Packages, Sources
//!TODO: Implement HTTP authentication or make the user put it into the url
- (void)obtainIndices {
    [self obtainReleaseIndexWithCompression:CPRepositoryIndexCompressionNone];
}

//!TODO: utilize FMDB's database queue for multitheading
- (void)obtainPackagesIndexWithCompression:(CPRepositoryIndexCompression)compression {
    if (compression > CPRepositoryIndexCompressionNone) {
        // error...
        return;
    }
    
    // find the appropriate url for the packages index
    NSURL *packagesURL = [self urlForIndex:CPRepositoryIndexPackages withFormat:self.format];
    
    // append correct extension for compression
    NSString *ext = extensionForCompression(compression);
    if (ext.length > 0) {
        packagesURL = [packagesURL URLByAppendingPathExtension:ext];
    }
    
    __weak CPRepository *weakSelf = self;
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
                                NSDictionary *dict = dictionarize(segment);
                                if (dict.count == 0) {
                                    continue;
                                }
                                
                                // update the database value
                                NSString *query = [NSString stringWithFormat:@"insert or replace into packages (%@) values (:%@)",
                                                   [dict.allKeys componentsJoinedByString:@", "],
                                                   [dict.allKeys componentsJoinedByString:@", :"]];
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

- (void)obtainReleaseIndexWithCompression:(CPRepositoryIndexCompression)compression {
    if (compression > CPRepositoryIndexCompressionNone) {
        if (self.format < CPRepositoryFormatModern) {
            self.format++;
            [self obtainReleaseIndexWithCompression:0];
            return;
        }
        // error...
        return;
    }
    
    NSURL *releaseURL = [self urlForIndex:CPRepositoryIndexRelease
                               withFormat:self.format];
    NSString *ext = extensionForCompression(compression);
    if (ext.length > 0) {
        releaseURL = [releaseURL URLByAppendingPathExtension:ext];
    }
    
    __weak CPRepository *weakSelf = self;
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
                                   NSDictionary *information = dictionarize(strRep);
                                   [weakSelf.databaseQueue inDatabase:^(FMDatabase *db) {
                                       [db executeUpdate:@"insert into release values (:architectures, :codename, :components, :description, :label, :suite, :version, :origin)" withParameterDictionary:information];
                                       
                                       [weakSelf updateRepositoryInformationFromDatabase: db];
                                   }];
                                   
                                   [weakSelf obtainPackagesIndexWithCompression:CPRepositoryIndexCompressionLZMA];
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

- (NSArray *)listPackages {
    __block NSMutableArray *list = [NSMutableArray array];
    
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *results = [db executeQuery:@"select package, name, description, icon, version, section from packages"];

        NSDictionary *map = results.columnNameToIndexMap;
        while ([results next]) {
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            for (NSString *key in map) {
                id value = [results objectForColumnName:key];
                if (value && ![value isKindOfClass:[NSNull class]]) {
                    dict[key] = value;
                }
            }
            
            [list addObject:dict];
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
        NSDictionary *map = results.columnNameToIndexMap;
        while ([results next]) {
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            for (NSString *key in map) {
                id value = [results objectForColumnName:key];
                if (value && ![value isKindOfClass:[NSNull class]]) {
                    dict[key] = value;
                }
            }
            
            [list addObject:dict];
        }
        
        [results close];
        
    }];
    
    return list;
}

- (NSDictionary *)packageWithIdentifier:(NSString *)identifier {
    __block NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        NSString *query = [NSString stringWithFormat:@"select * from packages where package is '%@' limit 2", identifier];
        FMResultSet *results = [db executeQuery:query];
        NSDictionary *map = results.columnNameToIndexMap;
        
        [results next];
        for (NSString *key in map) {
            id value = [results objectForColumnName:key];
            if (value && ![value isKindOfClass:[NSNull class]]) {
                dict[key] = value;
            }
        }
        
        [results next];
        if (results.hasAnotherRow) {
            NSLog(@"too many items with the same identifier");
            dict = nil;
        }
        
        [results close];
    }];
    
    return dict;
}

- (NSURL *)urlForIndex:(CPRepositoryIndex)index withFormat:(CPRepositoryFormat)format {
    NSString *components = @"";
    switch (format) {
        case CPRepositoryFormatFlat:
            switch (index) {
                case CPRepositoryIndexRelease:
                    components = @"Release";
                    break;
                case CPRepositoryIndexPackages:
                    components = @"Packages";
                    break;
                case CPRepositoryIndexSources:
                    components = @"Sources";
                    break;
                default:
                    break;
            }
            break;
        case CPRepositoryFormatModern:
            switch (index) {
                case CPRepositoryIndexRelease:
                    components = @"dists/stable/Release";
                    break;
                case CPRepositoryIndexPackages: {
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
                case CPRepositoryIndexSources:
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
