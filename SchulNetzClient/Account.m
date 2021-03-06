#import "Account.h"
#import "Parser.h"
#import "Util.h"
#import "Data/User.h"

@interface Account (){
	NSMutableArray* pageQueue;
	dispatch_queue_t pageDQ;
	
	NSMutableArray* scheduleQueue;
	dispatch_queue_t scheduleDQ;
}
@end

@implementation Account
@synthesize host;
@synthesize username;
@synthesize password;

@synthesize signedIn;

-(instancetype)initWithUsername:(NSString*)username password:(NSString*)password host: (NSString*)host{
	return [self initWithUsername:username password:password host:host session:true];
}

-(instancetype)initWithUsername:(NSString*)username password:(NSString*)password host: (NSString*)host session:(BOOL)session{
	self.host = host;
    self.username = username;
    self.password = password;
	
	cookiesList = [[NSMutableArray alloc] init];
	
	pageQueue = [[NSMutableArray alloc] init];
	pageDQ = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
	
	scheduleQueue = [[NSMutableArray alloc] init];
	scheduleDQ = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
	
	if(session) manager = [[SessionManager alloc] initWithAccount:self];
	
	self = [super init];
    return self;
}

-(instancetype)initFromCredentials{
	return [self initFromCredentials:true];
}

-(instancetype)initFromCredentials:(BOOL)session{
	UICKeyChainStore* keyChain = [Util getKeyChain];
	return [self initWithUsername:keyChain[@"username"] password:keyChain[@"password"] host: [[NSUserDefaults standardUserDefaults] objectForKey:@"host"] session:session];
}

-(void)saveCredentials{
	[[NSUserDefaults standardUserDefaults] setObject:host forKey:@"host"];
	
	UICKeyChainStore* keyChain = [Util getKeyChain];
	keyChain[@"username"] = username;
	keyChain[@"password"] = password;
	
    [[NSUserDefaults standardUserDefaults] setBool:true forKey:@"loggedIn"];
}

+(void)deleteCredentials{
	UICKeyChainStore* keyChain = [Util getKeyChain];
	keyChain[@"username"] = nil;
	keyChain[@"password"] = nil;
	
    [[NSUserDefaults standardUserDefaults] setBool:false forKey:@"loggedIn"];
}

-(NSObject*)signIn{
	while(signingOut) {
		NSDate *date = [[NSDate alloc] initWithTimeIntervalSinceNow:0.1];
		[[NSRunLoop currentRunLoop] runUntilDate:date];
	}
	
	if(signingIn) return [NSNumber numberWithBool:false];
	
	@try{
		signingIn = true;
		
		NSURLSession* defaultSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
		
		NSURL* loginUrl = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@/", host]];
		NSMutableURLRequest* urlRequest = [NSMutableURLRequest requestWithURL:loginUrl];
		
		[urlRequest setHTTPMethod:@"GET"];
		[urlRequest setValue:@"SchulNetz Client" forHTTPHeaderField:@"User-Agent"];
		
		__block HTMLDocument* loginSrc;
		
		__block BOOL done = NO;
		__block NSError* exception = NULL;
		
		NSURLSessionDataTask *dataTask = [defaultSession dataTaskWithRequest:urlRequest completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
			if(error != NULL || data == NULL){
				exception = error;
				done = YES;
				return;
			}
			
			NSDictionary* headers = [(NSHTTPURLResponse*) response allHeaderFields];
			loginSrc = [[HTMLDocument alloc] initWithData:data contentTypeHeader:headers[@"Content-Type"]];
			
			self->currentCookies = [self getCookies:headers];
			
			done = YES;
		}];
		[dataTask resume];
		
		while (!done) {
			NSDate *date = [[NSDate alloc] initWithTimeIntervalSinceNow:0.1];
			[[NSRunLoop currentRunLoop] runUntilDate:date];
		}
		
		if(exception){
			signingIn = false;
			return exception;
		}
		
		NSString* loginHash = [[[loginSrc nodesMatchingSelector:@"*[name=\"loginhash\"]"][0] attributes] valueForKey:@"value"];

		loginUrl = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@/index.php?pageid=1", host]];
		urlRequest = [NSMutableURLRequest requestWithURL:loginUrl];
		
		NSMutableString *postParams = [[NSMutableString alloc]initWithString:@"login="];
		[postParams appendString:self->username];
		[postParams appendString:@"&passwort="];
		[postParams appendString:self->password];
		[postParams appendString:@"&loginhash="];
		[postParams appendString:loginHash];
		
		NSData *postData = [postParams dataUsingEncoding:NSUTF8StringEncoding];
		
		[urlRequest setHTTPMethod:@"POST"];
		[urlRequest setHTTPBody:postData];
		[urlRequest setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
		[urlRequest setValue:@"keep-alive" forHTTPHeaderField:@"Connection"];
		[urlRequest setValue:self->currentCookies forHTTPHeaderField:@"Cookie"];
		[urlRequest setValue:@"SchulNetz Client" forHTTPHeaderField:@"User-Agent"];
		
		__block HTMLDocument* pageSrc;
		
		done = false;
		dataTask = [defaultSession dataTaskWithRequest:urlRequest completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
			if(error != NULL || data == NULL){
				exception = error;
				done = YES;
				return;
			}
			
			pageSrc = [[HTMLDocument alloc] initWithData:data contentTypeHeader:[(NSHTTPURLResponse*) response allHeaderFields][@"Content-Type"]];
			
			self->currentCookies = [self getCookies:[(NSHTTPURLResponse*)response allHeaderFields]];
			
			done = YES;
		}];
		[dataTask resume];
		
		while(!done) {
			NSDate *date = [[NSDate alloc] initWithTimeIntervalSinceNow:0.1];
			[[NSRunLoop currentRunLoop] runUntilDate:date];
		}
		
		HTMLElement* navBar = [pageSrc firstNodeMatchingSelector:@"#nav-main-menu"];
		if(!navBar){
			signingIn = false;
			return [NSNumber numberWithBool:false];
		}
		
		self->currentTransId = [self getTransId:pageSrc];
		
		NSString* href = [[[navBar childElementNodes][0] attributes] valueForKey:@"href"];
		NSRange idRange = NSMakeRange([href rangeOfString:@"&id="].location + [@"&id=" length], [href rangeOfString:@"&transid="].location - [href rangeOfString:@"&id="].location - [@"&id=" length]);
		self->currentId = [href substringWithRange: idRange];
		
		if(exception){
			signingIn = false;
			return exception;
		}
		
		if(currentId.length <= 0) {
			signingIn = false;
			return [NSNumber numberWithBool:false];
		}
		
		if(manager) [manager start];
		signedIn = true;
		
		signingIn = false;
		return [NSNumber numberWithBool:true];
	} @catch(NSException* exception){
		signingIn = false;
		return exception;
	} @finally{}
}

-(NSObject*)signOut{
	return [self signOut:false];
}

-(NSObject*)signOut:(BOOL)instant{
	if(signingOut || !signedIn) return [NSNumber numberWithBool:true];
	
	@try {
		signingOut = true;
		
		if(!instant) while(pageQueue.count > 0 || scheduleQueue.count > 0) {
			NSDate *date = [[NSDate alloc] initWithTimeIntervalSinceNow:0.1];
			[[NSRunLoop currentRunLoop] runUntilDate:date];
		}
		
		NSURLSession *defaultSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
		
		NSMutableString *urlString = [[NSMutableString alloc]initWithFormat:@"https://%@/index.php?pageid=9999&id=", host];
		[urlString appendString:currentId];
		[urlString appendString:@"&transid="];
		[urlString appendString:currentTransId];
		
		NSURL *url = [NSURL URLWithString:urlString];
		NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:url];

		[urlRequest setHTTPMethod:@"GET"];
		[urlRequest setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
		[urlRequest setValue:@"keep-alive" forHTTPHeaderField:@"Connection"];
		[urlRequest setValue:self->currentCookies forHTTPHeaderField:@"Cookie"];
		[urlRequest setValue:@"SchulNetz Client" forHTTPHeaderField:@"User-Agent"];
		
		__block BOOL done = NO;
		__block NSError* exception;
		NSURLSessionDataTask *dataTask = [defaultSession dataTaskWithRequest:urlRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
			if(error != NULL || data == NULL) exception = error;
			
			done = YES;
		}];
		[dataTask resume];
		
		while (!done) {
			NSDate *date = [[NSDate alloc] initWithTimeIntervalSinceNow:0.5];
			[[NSRunLoop currentRunLoop] runUntilDate:date];
		}
		
		if(exception){
			signingOut = false;
			return exception;
		}
		
		currentId = currentTransId = currentCookies = @"";
		cookiesList = [[NSMutableArray alloc] init];
		
		if(manager) [manager stop];
		signedIn = false;
		
		signingOut = false;
		return [NSNumber numberWithBool:true];
	} @catch(NSException* exception){
		signingOut = false;
		return exception;
	} @finally{}
}

-(NSObject*)resetTimeout{
	if(!signedIn) return NULL;
	
	@try{
		NSURLSession *defaultSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];

		NSURL* loginUrl = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@/xajax_js.php?pageid=1&id=%@&transid=%@", host, currentId, currentTransId]];
		NSMutableURLRequest* urlRequest = [NSMutableURLRequest requestWithURL:loginUrl];
		
		NSMutableString *postParams = [[NSMutableString alloc]initWithString:@"xajax=reset_timeout&xajaxr="];
		[postParams appendString:[NSString stringWithFormat:@"%d", (int)([[NSDate date] timeIntervalSince1970] * 1000)]];
		
		NSData *postData = [postParams dataUsingEncoding:NSUTF8StringEncoding];
		
		[urlRequest setHTTPMethod:@"POST"];
		[urlRequest setHTTPBody:postData];
		[urlRequest setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
		[urlRequest setValue:@"keep-alive" forHTTPHeaderField:@"Connection"];
		[urlRequest setValue:self->currentCookies forHTTPHeaderField:@"Cookie"];
		[urlRequest setValue:@"SchulNetz Client" forHTTPHeaderField:@"User-Agent"];
		
		__block HTMLDocument* pageSrc;
		
		__block BOOL done = false;
		__block NSError* exception;
		NSURLSessionDataTask* dataTask = [defaultSession dataTaskWithRequest:urlRequest completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
			if(error != NULL || data == NULL){
				exception = error;
				done = YES;
				return;
			}
			
			pageSrc = [[HTMLDocument alloc] initWithData:data contentTypeHeader:[(NSHTTPURLResponse*) response allHeaderFields][@"Content-Type"]];
			
			done = YES;
		}];
		[dataTask resume];
		
		while (!done) {
			NSDate *date = [[NSDate alloc] initWithTimeIntervalSinceNow:0.1];
			[[NSRunLoop currentRunLoop] runUntilDate:date];
		}
		
		if(exception) return exception;
		else return [NSNumber numberWithBool:true];
	} @catch(NSException *exception){
		return exception;
	} @finally{}
}

-(void)loadPage:(NSString*)pageId completion:(void (^)(NSObject*))completion{
	if((!signedIn && !signingIn) || signingOut) return;
	
	NSMutableDictionary* d = [[NSMutableDictionary alloc] init];
	d[@"pageId"] = pageId;
	d[@"completion"] = completion;
	[pageQueue addObject:d];
	
	if(pageQueue.count > 1) return;
	
	dispatch_async(pageDQ, ^{
		while(self->pageQueue.count > 0){
			NSMutableDictionary* dict = self->pageQueue[0];
			
			NSObject* result = [self loadPage:dict[@"pageId"]];
			if(self->pageQueue.count > 0) [self->pageQueue removeObjectAtIndex:0];
			
			dispatch_async(dispatch_get_main_queue(), ^{
				((void (^)(NSObject*))dict[@"completion"])(result);
			});
		}
	});
}

-(NSObject*)loadPage:(NSString*)pageId{
	if(!signedIn && !signingIn) [self signIn];
	
	while(signingIn) {
		NSDate *date = [[NSDate alloc] initWithTimeIntervalSinceNow:0.5];
		[[NSRunLoop currentRunLoop] runUntilDate:date];
	}
	
	if(!signedIn) return NULL;
	
	@try {
		__block HTMLDocument* src;
		
		NSURLSession *defaultSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
		
		NSMutableString *urlString = [[NSMutableString alloc]initWithFormat:@"https://%@/index.php?pageid=", host];
		[urlString appendString:pageId];
		[urlString appendString:@"&id="];
		[urlString appendString:currentId];
		[urlString appendString:@"&transid="];
		[urlString appendString:currentTransId];
		
		NSURL *url = [NSURL URLWithString:urlString];
		NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:url];

		[urlRequest setHTTPMethod:@"GET"];
		[urlRequest setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
		[urlRequest setValue:@"keep-alive" forHTTPHeaderField:@"Connection"];
		[urlRequest setValue:self->currentCookies forHTTPHeaderField:@"Cookie"];
		[urlRequest setValue:@"SchulNetz Client" forHTTPHeaderField:@"User-Agent"];
		
		__block BOOL done = NO;
		__block NSError* exception;
		NSURLSessionDataTask *dataTask = [defaultSession dataTaskWithRequest:urlRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
			if(error != NULL || data == NULL) {
				exception = error;
				done = YES;
				return;
			}
			
			src = [[HTMLDocument alloc] initWithData:data contentTypeHeader:[(NSHTTPURLResponse*) response allHeaderFields][@"Content-Type"]];
			
			self->currentCookies = [self getCookies: [(NSHTTPURLResponse*) response allHeaderFields]];
			self->currentTransId = [self getTransId:src];
			
			done = YES;
		}];
		[dataTask resume];
		
		while (!done) {
			NSDate *date = [[NSDate alloc] initWithTimeIntervalSinceNow:0.5];
			[[NSRunLoop currentRunLoop] runUntilDate:date];
		}
		
		if(exception) return exception;
		
		signedIn = [src nodesMatchingSelector:@"#nav-main-menu"].count > 0;
		if(!signedIn) return NULL;
		else return src;
	} @catch(NSException *exception){
		return exception;
	} @finally{}
}

-(void)loadScheduleFrom:(NSDate*)from to:(NSDate*)to completion:(void (^)(NSObject*))completion{
	[self loadScheduleFrom:from to:to view:@"day" completion:completion];
}

-(void)loadScheduleFrom:(NSDate*)from to:(NSDate*)to view:(NSString*)view completion:(void (^)(NSObject*))completion{
	NSMutableDictionary* d = [[NSMutableDictionary alloc] init];
	d[@"from"] = from;
	d[@"to"] = to;
	d[@"view"] = view;
	d[@"completion"] = completion;
	
	if(scheduleQueue.count > 1) [scheduleQueue removeObjectAtIndex:1];
	[scheduleQueue addObject:d];
	
	if(scheduleQueue.count > 1) return;
	
	dispatch_async(scheduleDQ, ^{
		while(self->scheduleQueue.count > 0){
			NSMutableDictionary* dict = self->scheduleQueue[0];
			
			NSObject* result = [self loadScheduleFrom:dict[@"from"] to:dict[@"to"] view:d[@"view"]];
			if(self->scheduleQueue.count > 0) [self->scheduleQueue removeObjectAtIndex:0];
			
			dispatch_async(dispatch_get_main_queue(), ^{
				((void (^)(NSObject*))dict[@"completion"])(result);
			});
		}
	});
}

-(NSObject*)loadScheduleFrom:(NSDate*)from to:(NSDate*)to view:(NSString*)view{
	if((!signedIn && !signingIn) || signingOut || !currentId) return NULL;
	
	while(signingIn || pageQueue.count > 0) {
		NSDate *date = [[NSDate alloc] initWithTimeIntervalSinceNow:0.5];
		[[NSRunLoop currentRunLoop] runUntilDate:date];
	}
	
	if(!signedIn) return NULL;
	
	@try {
		NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
		formatter.dateFormat = @"yyyy-MM-dd";
		
		NSDateComponents* comp = [[NSDateComponents alloc] init];
		comp.day = 1;
		
		to = [[NSCalendar currentCalendar] dateByAddingComponents:comp toDate:to options:0];
		
		__block HTMLDocument* src;
		
		NSURLSession *defaultSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
		
		NSMutableString *urlString = [[NSMutableString alloc] initWithFormat:@"https://%@/scheduler_processor.php?view=", host];
		[urlString appendString:view];
		[urlString appendString:@"&curr_date=2005-05-10&min_date="];
		[urlString appendString:[formatter stringFromDate:from]];
		[urlString appendString:@"&max_date="];
		[urlString appendString:[formatter stringFromDate:to]];
		[urlString appendString:@"&ansicht=schueleransicht&id="];
		[urlString appendString:currentId];
		[urlString appendString:@"&transid=potato&pageid=22202"];
		
		NSURL *url = [NSURL URLWithString:urlString];
		NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:url];

		[urlRequest setHTTPMethod:@"GET"];
		urlRequest.timeoutInterval = 15;
		[urlRequest setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
		[urlRequest setValue:@"keep-alive" forHTTPHeaderField:@"Connection"];
		[urlRequest setValue:self->currentCookies forHTTPHeaderField:@"Cookie"];
		[urlRequest setValue:@"SchulNetz Client" forHTTPHeaderField:@"User-Agent"];
		
		__block BOOL done = NO;
		__block NSError* exception;
		NSURLSessionDataTask *dataTask = [defaultSession dataTaskWithRequest:urlRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
			if(error != NULL || data == NULL) {
				exception = error;
				done = YES;
				return;
			}
			
			src = [[HTMLDocument alloc] initWithData:data contentTypeHeader:[(NSHTTPURLResponse*) response allHeaderFields][@"Content-Type"]];
			
			done = YES;
		}];
		[dataTask resume];
		
		while (!done) {
			NSDate *date = [[NSDate alloc] initWithTimeIntervalSinceNow:0.5];
			[[NSRunLoop currentRunLoop] runUntilDate:date];
		}
		
		if(exception) return exception;
		else return src;
	} @catch(NSException *exception){
		return exception;
	} @finally{}
}

-(NSString*)getTransId:(HTMLDocument*)src{
	NSString* transId = @"";
	
	HTMLElement* navBar = [src firstNodeMatchingSelector:@"*[id=\"nav-main-menu\"]"];
	NSString* href = [[[navBar childElementNodes][0] attributes] valueForKey:@"href"];
	transId = [href substringFromIndex: [href rangeOfString:@"transid="].location + [@"transid=" length]];
	
	return transId;
}

-(NSString*)getCookies:(NSDictionary*)headers{
	NSMutableString* cookies = [[NSMutableString alloc] init];
	
	NSMutableString* setCookie = [headers valueForKey:@"Set-Cookie"] ? [[NSMutableString alloc] initWithString:(NSString*)[headers valueForKey:@"Set-Cookie"]] : [[NSMutableString alloc] initWithString:@""];
	if([setCookie rangeOfString:@", \\d" options:NSRegularExpressionSearch].location != NSNotFound) [setCookie replaceCharactersInRange:NSMakeRange([setCookie rangeOfString:@", \\d" options:NSRegularExpressionSearch].location, 1) withString:@""];
	
	for(NSString* value in [setCookie componentsSeparatedByString:@","]){
		BOOL existing = false;
		
		for(NSString* old in cookiesList){
			if([[value substringToIndex:[value rangeOfString:@"="].location] isEqualToString:[old substringToIndex:[old rangeOfString:@"="].location]]) {
				[cookiesList setObject:value atIndexedSubscript:[cookiesList indexOfObject:old]];
				existing = true;
				break;
			}
		}
		
		if(!existing) [cookiesList addObject:value];
	}
	
	for(NSString* value in cookiesList){
		if([cookies length] > 0) [cookies appendString:@";"];
		
		[cookies appendString:([value rangeOfString:@";"].location) >= 0 ? [value substringToIndex:[value rangeOfString:@";"].location] : value];
	}
	
	return cookies;
}

-(void)close{
	if(manager){
		[manager stop];
		manager = NULL;
	}
	
	if(signedIn && !signingOut) [self signOut];
}
@end
