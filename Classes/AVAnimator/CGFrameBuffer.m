//
//  CGFrameBuffer.m
//  AVAnimatorDemo
//
//  Created by Moses DeJong on 2/13/09.
//
//  License terms defined in License.txt.

#import "CGFrameBuffer.h"

#import <QuartzCore/QuartzCore.h>

#define DEBUG_LOGGING

void CGFrameBufferProviderReleaseData (void *info, const void *data, size_t size);

@implementation CGFrameBuffer

@synthesize pixels = m_pixels;
@synthesize numBytes = m_numBytes;
@synthesize width = m_width;
@synthesize height = m_height;
@synthesize bitsPerPixel = m_bitsPerPixel;
@synthesize bytesPerPixel = m_bytesPerPixel;
//@synthesize isLockedByDataProvider = m_isLockedByDataProvider;
@synthesize lockedByImageRef = m_lockedByImageRef;

+ (CGFrameBuffer*) cGFrameBufferWithBppDimensions:(NSInteger)bitsPerPixel width:(NSInteger)width height:(NSInteger)height
{
  CGFrameBuffer *obj = [[CGFrameBuffer alloc] initWithBppDimensions:bitsPerPixel width:width height:height];
  [obj autorelease];
  return obj;
}

- (id) initWithBppDimensions:(NSInteger)bitsPerPixel width:(NSInteger)width height:(NSInteger)height;
{
	// Ensure that memory is allocated in terms of whole words, the
	// bitmap context won't make use of the extra half-word.

	size_t numPixels = width * height;
	size_t numPixelsToAllocate = numPixels;

	if ((numPixels % 2) != 0) {
		numPixelsToAllocate++;
	}

  // 16bpp -> 2 bytes per pixel, 24bpp and 32bpp -> 4 bytes per pixel
  
  int bytesPerPixel;
  if (bitsPerPixel == 16) {
    bytesPerPixel = 2;
  } else if (bitsPerPixel == 24 || bitsPerPixel == 32) {
    bytesPerPixel = 4;
  } else {
    NSAssert(FALSE, @"bitsPerPixel is invalid");
  }
  
	int inNumBytes = numPixelsToAllocate * bytesPerPixel;

  // FIXME: Use valloc(size) to allocate memory that is always aligned to a whole page.
  // Also, it might be useful to ensure that some number of whole pages is returned,
  // so make the size in terms on bytes large enough (round up to the page size).
  // int getpagesize(void); returns the value. Could a memcpy() then know that whole
  // pages needed to be copied, would this faster?

  // Mac OS X supports vm_copy() and vm_alloc(), look into an impl that makes use of
  // defered copy ?
  
  // Test impl of both of these.
	char* buffer = (char*) malloc(inNumBytes);

	if (buffer == NULL) {
		return nil;
  }

	memset(buffer, 0, inNumBytes);

  if (self = [super init]) {
    self->m_bitsPerPixel = bitsPerPixel;
    self->m_bytesPerPixel = bytesPerPixel;
    self->m_pixels = buffer;
    self->m_numBytes = inNumBytes;
    self->m_width = width;
    self->m_height = height;
  } else {
    free(buffer);
  }

	return self;
}

- (BOOL) renderView:(UIView*)view
{
	// Capture the pixel content of the View that contains the
	// UIImageView. A view that displays at the full width and
	// height of the screen will be captured in a 320x480
	// bitmap context. Note that any transformations applied
	// to the UIImageView will be captured *after* the
	// transformation has been applied. Once the bitmap
	// context has been captured, it should be rendered with
	// no transformations. Also note that the colorspace
	// is always ARGBwith no alpha, the bitmap capture happens
	// *after* any colors in the image have been converted to RGB pixels.

	size_t w = view.layer.bounds.size.width;
	size_t h = view.layer.bounds.size.height;

//	if ((self.width != w) || (self.height != h)) {
//		return FALSE;
//	}

	BOOL isRotated;

	if ((self.width == w) && (self.height == h)) {
		isRotated = FALSE;
	} else if ((self.width == h) || (self.height != w)) {
		// view must have created a rotation transformation
		isRotated = TRUE;
	} else {
		return FALSE;
	}
  
  size_t bitsPerComponent;
  size_t numComponents;
  size_t bitsPerPixel;
  size_t bytesPerRow;
  
  if (self.bitsPerPixel == 16) {
    bitsPerComponent = 5;
    numComponents = 3;
    bitsPerPixel = 16;
    bytesPerRow = self.width * (bitsPerPixel / 8);    
  } else if (self.bitsPerPixel == 24 || self.bitsPerPixel == 32) {
    bitsPerComponent = 8;
    numComponents = 4;
    bitsPerPixel = bitsPerComponent * numComponents;
    bytesPerRow = self.width * (bitsPerPixel / 8);
  } else {
    NSAssert(FALSE, @"unmatched bitsPerPixel");
  }

	CGBitmapInfo bitmapInfo = [self getBitmapInfo];

	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

	NSAssert(self.pixels != NULL, @"pixels must not be NULL");

	NSAssert(self.isLockedByDataProvider == FALSE, @"renderView: pixel buffer locked by data provider");

	CGContextRef bitmapContext =
		CGBitmapContextCreate(self.pixels, self.width, self.height, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo);

	CGColorSpaceRelease(colorSpace);

	if (bitmapContext == NULL) {
		return FALSE;
	}

	// Translation matrix that maps CG space to view space

	CGContextTranslateCTM(bitmapContext, 0.0, self.height);
	CGContextScaleCTM(bitmapContext, 1.0, -1.0);

	[view.layer renderInContext:bitmapContext];

	CGContextRelease(bitmapContext);

	return TRUE;
}

- (BOOL) renderCGImage:(CGImageRef)cgImageRef
{
	// Render the contents of an image to pixels.

	size_t w = CGImageGetWidth(cgImageRef);
	size_t h = CGImageGetHeight(cgImageRef);
	
	BOOL isRotated = FALSE;
	
	if ((self.width == w) && (self.height == h)) {
		// pixels will render as expected
	} else if ((self.width == h) || (self.height != w)) {
		// image should be rotated before rendering
		isRotated = TRUE;
	} else {
		return FALSE;
	}
	
  size_t bitsPerComponent;
  size_t numComponents;
  size_t bitsPerPixel;
  size_t bytesPerRow;
  
  if (self.bitsPerPixel == 16) {
    bitsPerComponent = 5;
    numComponents = 3;
    bitsPerPixel = 16;
    bytesPerRow = self.width * (bitsPerPixel / 8);    
  } else if (self.bitsPerPixel == 24 || self.bitsPerPixel == 32) {
    bitsPerComponent = 8;
    numComponents = 4;
    bitsPerPixel = bitsPerComponent * numComponents;
    bytesPerRow = self.width * (bitsPerPixel / 8);
  } else {
    NSAssert(FALSE, @"unmatched bitsPerPixel");
  }
  
	CGBitmapInfo bitmapInfo = [self getBitmapInfo];
	
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

	NSAssert(self.pixels != NULL, @"pixels must not be NULL");
	NSAssert(self.isLockedByDataProvider == FALSE, @"renderCGImage: pixel buffer locked by data provider");

	CGContextRef bitmapContext =
		CGBitmapContextCreate(self.pixels, self.width, self.height, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo);
	
	CGColorSpaceRelease(colorSpace);
	
	if (bitmapContext == NULL) {
		return FALSE;
	}
	
	// Translation matrix that maps CG space to view space

	if (isRotated) {
		// To landscape : 90 degrees CCW

		CGContextRotateCTM(bitmapContext, M_PI / 2);		
	}

	CGRect bounds = CGRectMake( 0.0f, 0.0f, self.width, self.height );

	CGContextDrawImage(bitmapContext, bounds, cgImageRef);
	
	CGContextRelease(bitmapContext);
	
	return TRUE;
}

- (CGImageRef) createCGImageRef
{
	// Load pixel data as a core graphics image object.

  NSAssert(self.width > 0 && self.height > 0, @"width or height is zero");

  size_t bitsPerComponent;
  size_t numComponents;
  size_t bitsPerPixel;
  size_t bytesPerRow;
  
  if (self.bitsPerPixel == 16) {
    bitsPerComponent = 5;
    numComponents = 3;
    bitsPerPixel = 16;
    bytesPerRow = self.width * (bitsPerPixel / 8);    
  } else if (self.bitsPerPixel == 24 || self.bitsPerPixel == 32) {
    bitsPerComponent = 8;
    numComponents = 4;
    bitsPerPixel = bitsPerComponent * numComponents;
    bytesPerRow = self.width * (bitsPerPixel / 8);
  } else {
    NSAssert(FALSE, @"unmatched bitsPerPixel");
  }  

	CGBitmapInfo bitmapInfo = [self getBitmapInfo];

	CGDataProviderReleaseDataCallback releaseData = CGFrameBufferProviderReleaseData;

	CGDataProviderRef dataProviderRef = CGDataProviderCreateWithData(self,
																	 self.pixels,
																	 self.width * self.height * (bitsPerPixel / 8),
																	 releaseData);

	BOOL shouldInterpolate = FALSE; // images at exact size already

	CGColorRenderingIntent renderIntent = kCGRenderingIntentDefault;

	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

	CGImageRef inImageRef = CGImageCreate(self.width, self.height, bitsPerComponent, bitsPerPixel, bytesPerRow,
										  colorSpace, bitmapInfo, dataProviderRef, NULL,
										  shouldInterpolate, renderIntent);

	CGDataProviderRelease(dataProviderRef);

	CGColorSpaceRelease(colorSpace);

	if (inImageRef != NULL) {
		self.isLockedByDataProvider = TRUE;
		self->m_lockedByImageRef = inImageRef; // Don't retain, just save pointer
	}

	return inImageRef;
}

- (BOOL) isLockedByImageRef:(CGImageRef)cgImageRef
{
	if (! self->m_isLockedByDataProvider)
		return FALSE;

	return (self->m_lockedByImageRef == cgImageRef);
}

- (CGBitmapInfo) getBitmapInfo
{
	CGBitmapInfo bitmapInfo = 0;
  if (self.bitsPerPixel == 16) {
    bitmapInfo = kCGBitmapByteOrder16Host | kCGImageAlphaNoneSkipFirst;
  } else if (self.bitsPerPixel == 24) {
    bitmapInfo |= kCGBitmapByteOrder32Host | kCGImageAlphaNoneSkipFirst;
  } else if (self.bitsPerPixel == 32) {
    bitmapInfo |= kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst;
  } else {
    assert(0);
  }
	return bitmapInfo;
}

// These properties are implemented explicitly to aid
// in debugging of read/write operations. These method
// are used to set values that could be set in one thread
// and read or set in another. The code must take care to
// use these fields correctly to remain thread safe.

- (BOOL) isLockedByDataProvider
{
	return self->m_isLockedByDataProvider;
}

- (void) setIsLockedByDataProvider:(BOOL)newValue
{
	NSAssert(m_isLockedByDataProvider == !newValue,
			 @"isLockedByDataProvider property can only be switched");

	self->m_isLockedByDataProvider = newValue;

	if (m_isLockedByDataProvider) {
		[self retain]; // retain extra ref to self
	} else {
#ifdef DEBUG_LOGGING
		if (TRUE)
#else
		if (FALSE)
#endif
		{
			// Catch the case where the very last ref to
			// an object is dropped fby CoreGraphics
			
			int refCount = [self retainCount];

			if (refCount == 1) {
				// About to drop last ref to this frame buffer

				NSLog(@"dropping last ref to CGFrameBuffer held by DataProvider");
			}

			[self release];
		} else {
			// Regular logic for non-debug situations

			[self release]; // release extra ref to self
		}
	}
}

- (void) copyPixels:(CGFrameBuffer *)anotherFrameBuffer
{
  assert(self.numBytes == anotherFrameBuffer.numBytes);
  memcpy(self.pixels, anotherFrameBuffer.pixels, anotherFrameBuffer.numBytes);
}

- (void)dealloc {
	NSAssert(self.isLockedByDataProvider == FALSE, @"dealloc: buffer still locked by data provider");

	if (self.pixels != NULL) {
		free(self.pixels);
  }

#ifdef DEBUG_LOGGING
	NSLog(@"deallocate CGFrameBuffer");
#endif

    [super dealloc];
}

@end

// C callback invoked by core graphics when done with a buffer, this is tricky
// since an extra ref is held on the buffer while it is locked by the
// core graphics layer.

void CGFrameBufferProviderReleaseData (void *info, const void *data, size_t size) {
#ifdef DEBUG_LOGGING
	NSLog(@"CGFrameBufferProviderReleaseData() called");
#endif

	CGFrameBuffer *cgBuffer = (CGFrameBuffer *) info;
	cgBuffer.isLockedByDataProvider = FALSE;

	// Note that the cgBuffer just deallocated itself, so the
	// pointer no longer points to a valid memory.
}
