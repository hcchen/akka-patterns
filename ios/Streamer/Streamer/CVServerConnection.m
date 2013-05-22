#import "CVServerConnection.h"
#import "BlockingQueueInputStream.h"
#import "AFNetworking/AFHTTPRequestOperation.h"
#import "AFNetworking/AFHTTPClient.h"
#import "i264Encoder.h"

typedef enum {
	kCVServerConnecitonStatic,
	kCVServerConnecitonStream
} CVServerConnectionMode;

@interface AbstractCVServerConnectionInput : NSObject {
@protected
	NSURL* url;
	id<CVServerConnectionDelegate> delegate;
}
- (id)initWithUrl:(NSURL*)url andDelegate:(id<CVServerConnectionDelegate>)delegate;
- (void)initConnectionInput;
@end

@interface CVServerConnectionInputStatic : AbstractCVServerConnectionInput<CVServerConnectionInput>
@end

@interface CVServerConnectionInputStream : AbstractCVServerConnectionInput<CVServerConnectionInput> {
	i264Encoder* encoder;
}
- (void)oni264Encoder:(i264Encoder *)encoder completedFrameData:(NSData *)data;
@end


@implementation CVServerConnection {
	NSURL *url;
	CVServerConnectionMode mode;
	id<CVServerConnectionDelegate> delegate;
}

- (id)initWithUrl:(NSURL *)aUrl delegate:(id<CVServerConnectionDelegate>)aDelegate andMode:(CVServerConnectionMode)aMode {
	self = [super init];
	if (self) {
		url = aUrl;
		delegate = aDelegate;
		mode = aMode;
	}
	
	return self;
}

+ (CVServerConnection*)connectionToStatic:(NSURL *)url andDelegate:(id<CVServerConnectionDelegate>)delegate {
	return [[CVServerConnection alloc] initWithUrl:url delegate:delegate andMode:kCVServerConnecitonStatic];
}

+ (CVServerConnection*)connectionToStream:(NSURL *)url andDelegate:(id<CVServerConnectionDelegate>)delegate {
	return [[CVServerConnection alloc] initWithUrl:url delegate:delegate andMode:kCVServerConnecitonStream];
}

- (id<CVServerConnectionInput>)begin {
	switch (mode) {
		case kCVServerConnecitonStatic:
			return [[CVServerConnectionInputStatic alloc] initWithUrl:url andDelegate:delegate];
		case kCVServerConnecitonStream:
			return [[CVServerConnectionInputStream alloc] initWithUrl:url andDelegate:delegate];
	}
}

@end

@implementation AbstractCVServerConnectionInput

- (id)initWithUrl:(NSURL*)aUrl andDelegate:(id<CVServerConnectionDelegate>)aDelegate {
	self = [super init];
	if (self) {
		url = aUrl;
		delegate = aDelegate;
	}
	return self;
}

- (void)initConnectionInput {
	// nothing in the abstract class
}

@end

/**
 * Uses plain JPEG encoding to submit the images from the incoming stream of frames
 */
@implementation CVServerConnectionInputStatic

- (void)submitFrame:(CMSampleBufferRef)frame {
	NSData* data = [@"FU" dataUsingEncoding:NSUTF8StringEncoding];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	[request setTimeoutInterval:30.0];
	[request setHTTPMethod:@"POST"];
	[request setHTTPBody:data];
	[request addValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
	AFHTTPRequestOperation* operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
	[operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
		NSLog(@":)");
		[delegate cvServerConnectionOk:responseObject];
	} failure:^(AFHTTPRequestOperation *operation, NSError *error) {
		NSLog(@":( %@", error);
	}];
	[operation start];
	[operation waitUntilFinished];
}

- (void)close {
	// This is a static connection. Nothing to see here.
}

@end

/**
 * Uses the i264 encoder to encode the incoming stream of frames. 
 */
@implementation CVServerConnectionInputStream {
	BlockingQueueInputStream *stream;
}

- (void)initConnectionInput {
	int framesPerSecond = 25;
	
	encoder = [[i264Encoder alloc] initWithDelegate:self];
	[encoder setInPicHeight:[NSNumber numberWithInt:480]];
	[encoder setInPicWidth:[NSNumber numberWithInt:720]];
	[encoder setFrameRate:[NSNumber numberWithInt:framesPerSecond]];
	[encoder setKeyFrameInterval:[NSNumber numberWithInt:framesPerSecond * 5]];
	[encoder setAvgDataRate:[NSNumber numberWithInt:100000]];
	[encoder setBitRate:[NSNumber numberWithInt:100000]];

	stream = [[BlockingQueueInputStream alloc] init];

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	[request setTimeoutInterval:30.0];
	[request setHTTPMethod:@"POST"];
	[request setHTTPBodyStream:stream];
	[request addValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
	AFHTTPRequestOperation* operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
	[operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
		NSLog(@":)");
		[delegate cvServerConnectionOk:responseObject];
	} failure:^(AFHTTPRequestOperation *operation, NSError *error) {
		NSLog(@":( %@", error);
	}];
	[operation start];
}

- (void)submitFrame:(CMSampleBufferRef)frame {
	CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(frame);
	[encoder encodePixelBuffer:pixelBuffer];
}

- (void)oni264Encoder:(i264Encoder *)encoder completedFrameData:(NSData *)data {
	[stream appendData:data];
}

- (void)close {
	[stream close];
}

@end