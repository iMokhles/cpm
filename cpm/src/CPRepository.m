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

NSString *baseify(NSURL *url) {
    NSString *scheme = url.scheme;
    NSString *substr = [url.absoluteString substringFromIndex:scheme.length + 3]; /* :// */
    return [[substr stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByReplacingOccurrencesOfString:@":" withString:@"@"];
}

NSDictionary *dictionarize(NSString *data) {
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
- (void)obtainIndices;
- (void)obtainReleaseIndexWithCompression:(CPRepositoryIndexCompression)compression;
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
        self.database = [FMDatabase databaseWithPath:dbPath];
        if (![self.database open]) {
            //!TODO: error
            NSLog(@"couldnt open database for writing");
            return nil;
        }
        
    }
    
    return self;
}

- (void)reloadData {
    [self.database executeUpdate:@"drop table if exists release"];
    [self.database executeUpdate:@"create table release (architectures text, codename text, components text, description text, label text, suite text, version text, origin text)"];
    [self.database executeUpdate:@"create table if not exists packages (package text primary key, size integer, version text, filename text, architecture text, maintainer text, installed_size integer, depends text, md5sum text, sha1 text, sha256 text, section text, priority text, homepage text, description text, author text, depiction text, sponsor text, icon text, name text)"];
    
    [self obtainIndices];
}

- (void)dealloc {
    [self.database close];
}

// Release, Packages, Sources
//!TODO: Implement HTTP authentication or make the user put it into the url
- (void)obtainIndices {
    [self obtainReleaseIndexWithCompression:CPRepositoryIndexCompressionNone];
}

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
            //!TODO: decide whether to decompress in-memory or write the data to file progressively, either way
            //! we have to load the data into ram
            @autoreleasepool {
                dispatch_async(dispatch_get_global_queue(0, DISPATCH_QUEUE_PRIORITY_HIGH), ^{
                    NSString *package = decompress(weakCurl.data);
                    if (!package) {
                        NSLog(@"could not decompress package data");
                        return;
                    }
                    
                    BOOL succ = YES;
                    
                    [package writeToFile:@"/Users/Alex/Desktop/a.txt" atomically:NO encoding:NSUTF8StringEncoding error:nil];
                    
                    [weakSelf.database beginTransaction];
                    NSRange range = NSMakeRange(0, package.length);
                    while (range.location != NSNotFound) {
                        @autoreleasepool {
                            if (!succ) {
                                NSLog(@"%@", self.database.lastErrorMessage);
                                [weakSelf.database rollback];
                                break;
                            }
                            NSRange nextRange = [package rangeOfString:@"\n\n"
                                                               options:NSLiteralSearch
                                                                 range:NSMakeRange(range.location + 2, package.length - range.location - 2)];
                            NSUInteger end = nextRange.location;
                            if (end == NSNotFound) {
                                end = package.length;
                            }
                            
                            NSString *segment = [package substringWithRange:NSMakeRange(range.location, end - range.location)];
                            range = nextRange;
                            
                            NSDictionary *dict = dictionarize(segment);
                            if (dict.count == 0) {
                                continue;
                            }
                            
                            NSString *query = [NSString stringWithFormat:@"insert or replace into packages (%@) values (:%@)",
                                               [dict.allKeys componentsJoinedByString:@", "],
                                               [dict.allKeys componentsJoinedByString:@", :"]];
                            succ = [weakSelf.database executeUpdate:query withParameterDictionary:dict];
                        }
                    }
                    
                    if (succ)
                        [weakSelf.database commit];
                });
            }
            NSLog(@"done parsing packages");
            //            }];
            
        }
    };
    
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
                                   NSLog(@"%@", dictionarize(strRep));
                                   [self.database executeUpdate:@"insert into release values (:architectures, :codename, :components, :description, :label, :suite, :version, :origin)" withParameterDictionary:dictionarize(strRep)];
                                   
                                   [self obtainPackagesIndexWithCompression:CPRepositoryIndexCompressionLZMA];
                               }
                           }];
}

- (NSArray *)listPackages {
    FMResultSet *results = [self.database executeQuery:@"select package, name, description, icon, version, section from packages"];
    NSMutableArray *list = [NSMutableArray array];
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
    
    return list;
}

- (NSArray *)searchForPackage:(NSString *)input {
    NSString *query = [NSString stringWithFormat:@"select package, name, description, icon, version, section from packages where name like '%%%@%%' limit 1", input];
    FMResultSet *results = [self.database executeQuery:query];
    NSMutableArray *list = [NSMutableArray array];
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
    return list;
}

- (NSURL *)downloadPackage:(NSString *)identifier {
    //!TODO: support non-flat repos
    
    NSString *query = [NSString stringWithFormat:@"select package, filename from packages where package is '%@'", identifier];
    FMResultSet *results = [self.database executeQuery:query];
    [results next];
    if (results.hasAnotherRow) {
        NSLog(@"too many items with the same identifier");
        return nil;
    }
    
    NSURL *remoteURL = [self.url URLByAppendingPathComponent:[results stringForColumn:@"filename"]];
    NSLog(@"%@", remoteURL);
    NSURL *localURL = [NSURL fileURLWithPath:[[NSTemporaryDirectory() stringByAppendingPathComponent:IDENTIFIER] stringByAppendingPathComponent:remoteURL.lastPathComponent]];
    [[NSFileManager defaultManager] createDirectoryAtURL:localURL.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    
    return localURL;
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
                    FMResultSet *results = [self.database executeQuery:@"select components from release"];
                    // use the first component from the release index
                    // if none specific, default to main
                    NSString *component = @"main";
                    if (results.next) {
                        NSString *res = [results stringForColumn:@"components"];
                        NSArray *separated = [res componentsSeparatedByString:@" "];
                        if (separated.count)
                            components = separated[0];
                    }
                    //!TODO: make sure architectures matches what we want somewhere, and if not, error out
                    components = [NSString stringWithFormat:@"dists/stable/%@/binary-iphoneos-arm/Packages", component];
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
