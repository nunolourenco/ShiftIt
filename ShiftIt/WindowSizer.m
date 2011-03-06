/*
 ShiftIt: Resize windows with Hotkeys
 Copyright (C) 2010  Aravind
 
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.
 
 */

#import <Carbon/Carbon.h>

#import "WindowSizer.h"
#import "ShiftIt.h"
#import "ShiftItAction.h"
#import "FMTDefines.h"
#import "AXUIUtils.h"
#import "X11Utils.h"

#define RECT_STR(rect) FMTStr(@"[%f %f] [%f %f]", (rect).origin.x, (rect).origin.y, (rect).size.width, (rect).size.height)
#define COCOA_TO_SCREEN_COORDINATES(rect) (rect).origin.y = [[NSScreen primaryScreen] frame].size.height - (rect).size.height - (rect).origin.y

// reference to the carbon GetMBarHeight() function
extern short GetMBarHeight(void);

@interface NSScreen (Private)

+ (NSScreen *)primaryScreen;
- (BOOL)isPrimary;

@end

@implementation NSScreen (Private)

+ (NSScreen *)primaryScreen {
	return [[NSScreen screens] objectAtIndex:0];
}

- (BOOL)isPrimary {
	return self == [NSScreen primaryScreen];
}

@end


#pragma mark Screen Implementation

@interface Screen ()

@property (readonly) BOOL belowPrimary_;
@property (readonly) NSRect screenFrame_;
@property (readonly) NSRect visibleFrame_;

@end

@implementation Screen

@dynamic size;
@dynamic belowPrimary_;
@synthesize primary = primary_;
@synthesize screenFrame_;
@synthesize visibleFrame_;

- (id) initWithNSScreen:(NSScreen *)screen {
	FMTAssertNotNil(screen);
	
	if (![super init]) {
		return nil;
	}
	
	// screen coordinates of the best fit window
	screenFrame_ = [screen frame];
	COCOA_TO_SCREEN_COORDINATES(screenFrame_);
	
	// visible screen coordinates of the best fit window
	// the visible screen denotes some inner rect of the screen frame
	// which is visible - not occupied by menu bar or dock
	visibleFrame_ = [screen visibleFrame];
	COCOA_TO_SCREEN_COORDINATES(visibleFrame_);
	
	primary_ = [screen isPrimary];
	
	return self;
}

- (NSSize) size {
	return visibleFrame_.size;
}

- (BOOL) belowPrimary_ { 			
	BOOL isBellow = NO;
	for (NSScreen *s in [NSScreen screens]) {
		NSRect r = [s frame];
		COCOA_TO_SCREEN_COORDINATES(r);
		if (r.origin.y > 0) {
			isBellow = YES;
			break;
		}
	}
	return isBellow;
}

@end

#pragma mark Window Implementation

@interface Window ()

@property (readonly) WindowId ref_;
@property (readonly) NSRect rect_;
@property (readonly) NSRect originalRect_;
@property (readonly) NSRect drawersRect_;
#ifdef X11
@property (readonly) BOOL x11win_;
@property (readonly) NSRect x11CoordRect_;
#endif

@end

@implementation Window

@dynamic origin;
@dynamic size;
@synthesize screen = screen_;
@synthesize ref_;
@synthesize rect_;
// TODO1: get rid of this 
@synthesize originalRect_;
@synthesize drawersRect_;
#ifdef X11
@synthesize x11win_;
@synthesize x11CoordRect_;
#endif

#ifdef X11
- (id) initWithId:(WindowId)ref rect:(NSRect)rect originalRect:(NSRect)originalRect drawersRect:(NSRect)drawersRect screen:(Screen *)screen x11win:(BOOL)x11win x11CoordRect:(NSRect)x11CoordRect {
#else
- (id) initWithId:(WindowId)ref rect:(NSRect)rect originalRect:(NSRect)originalRect drawersRect:(NSRect)drawersRect screen:(Screen *)screen {
#endif
	// TODO: check for invalid wids
	FMTAssertNotNil(ref);
	FMTAssertNotNil(screen);
	
	if (![super init]) {
		return nil;
	}
	
	ref_ = ref;
	rect_ = rect;
	originalRect_ = originalRect;
	drawersRect_ = drawersRect;
	screen_ = [screen retain];
#ifdef X11
	x11win_ = x11win;
	x11CoordRect_ = x11CoordRect;
#endif
	
	return self;
}

- (void) dealloc {
#ifdef X11
	if (x11win_) {
		X11FreeWindowRef(ref_);
	} else {
#endif
		AXUIFreeWindowRef(ref_);
#ifdef X11
	}
#endif
	
	[screen_ release];
	
	[super dealloc];
}

- (NSPoint) origin {
	return rect_.origin;
}

- (NSSize) size {
	return rect_.size;
}

@end

#pragma mark WindowManager Implementation

@interface WindowSizer (Private)

- (NSScreen *)chooseScreenForWindow_:(NSRect)windowRect;

@end

@implementation WindowSizer

static int X11Available_ = 0;

SINGLETON_BOILERPLATE(WindowSizer, sharedWindowSize);

- (id)init {
	if (![super init]) {
		return nil;
	}
	
#ifdef X11
	X11Available_ = InitializeX11Support();
#endif
	
	return self;
}

- (void) dealloc {
#ifdef X11
	DestoryX11Support();
#endif
	
	[super dealloc];
}

- (void) focusedWindow:(Window **)window error:(NSError **)error {

	// the window identifier - platform dependent
	WindowId windowId;

	// coordinates vars
	int x = 0, y = 0;
	unsigned int width = 0, height = 0;
	
	// drawers of the window
	NSRect drawersRect = {{0,0},{0,0}};
	
	// TODO1: extract
	BOOL useDrawers = [[NSUserDefaults standardUserDefaults] boolForKey:kIncludeDrawersPrefKey];
	
	// window rect
	NSRect windowRect;
	
#ifdef X11
	// X11 fun
	// TODO1: rename
	BOOL x11win = NO;
	NSRect x11CoordRect;
#endif
	
	// first try to get the window using accessibility API
	int ret = -1;
	
	if ((ret = AXUIGetActiveWindow(&windowId)) != 0) {
#ifdef X11
		if (X11Available_) {
			
			// try X11
			if ((ret = X11GetActiveWindow(&windowId)) != 0) {
				*error = CreateError(kUnableToGetActiveWindowErrorCode, FMTStrc(X11GetErrorMessage(ret)), nil);
				return;
			}
			
			if ((ret = X11GetWindowGeometry(windowId, &x, &y, &width, &height)) != 0) {
				*error = CreateError(kUnableToGetWindowGeometryErrorCode, FMTStrc(X11GetErrorMessage(ret)), nil);
				return;			
			}
			FMTDevLog(@"window rect (x11): [%d %d] [%d %d]", x, y, width, height);
			
			// following will make the X11 reference coordinate system
			// X11 coordinates starts at the very top left corner of the most top left window
			// basically it is a union of all screens with the beginning at the top left
			x11CoordRect = [[NSScreen primaryScreen] frame];
			for (NSScreen *screen in [NSScreen screens]) {
				x11CoordRect = NSUnionRect(x11CoordRect, [screen frame]);
			}
			// translate
			COCOA_TO_SCREEN_COORDINATES(x11CoordRect);
			FMTDevLog(@"X11 reference rect: %@", RECT_STR(x11CoordRect));
			
			// convert from X11 coordinates to Quartz CG coodinates
			x += x11CoordRect.origin.x;
			y += x11CoordRect.origin.y;
			
			windowRect.origin.x = x;
			windowRect.origin.y = y;
			windowRect.size.width = width;
			windowRect.size.height = height;
			
			x11win = YES;
		}
#else
		*error = CreateError(kUnableToGetActiveWindowErrorCode, FMTStrc(AXUIGetErrorMessage(ret)), nil);
		return;
#endif // X11
	} else {		
		if ((ret = AXUIGetWindowGeometry(windowId, &x, &y, &width, &height)) != 0) {
			*error = CreateError(kUnableToGetWindowGeometryErrorCode, FMTStrc(AXUIGetErrorMessage(ret)), nil);
			return;
		}
		
		windowRect.origin.x = x;
		windowRect.origin.y = y;
		windowRect.size.width = width;
		windowRect.size.height = height;
		
		// drawers
		if (useDrawers) {
			if ((ret = AXUIGetWindowDrawersUnionRect(windowId, &drawersRect)) != 0) {
				FMTDevLog(@"Unable to get window drawers: %d", ret);
			} else {
				FMTDevLog(@"Drawers: %@", RECT_STR(drawersRect));
			}
			
			if (drawersRect.size.width > 0) {
				windowRect = NSUnionRect(windowRect, drawersRect);
			}
		}
	}
	
	// get the screen which is the best fit for the window
	NSScreen *nsscreen = [self chooseScreenForWindow_:windowRect];
	FMTAssertNotNil(nsscreen);
	Screen *screen = [[Screen alloc] initWithNSScreen:nsscreen];
	
	NSRect originalRect = {
		{x,y},
		{width, height}
	};
	
#ifdef X11
	*window = [[Window alloc] initWithId:windowId rect:windowRect originalRect:originalRect drawersRect:drawersRect screen:screen x11win:x11win x11CoordRect:x11CoordRect];
#else
	*window = [[Window alloc] initWithId:windowId rect:windowRect originalRect:originalRect drawersRect:drawersRect screen:screen];
#endif
}

- (void) shiftWindow:(Window *)window to:(NSPoint)origin size:(NSSize)size screen:(Screen *)screen error:(NSError **)error {
	FMTAssertNotNil(window);
	
	int (*getWindowGeometryFn)(void *, int *, int *, unsigned int *, unsigned int *);
	int (*setWindowPositionFn)(void *, int, int);
	int (*setWindowSizeFn)(void *, unsigned int, unsigned int);
	void (*freeWindowRefFn)(void *);
	const char *(*getErrorMessageFn)(int);
	
#ifdef X11
	if ([window x11win_]) {
		getWindowGeometryFn = &X11GetWindowGeometry;
		setWindowPositionFn = &X11SetWindowPosition;
		setWindowSizeFn = &X11SetWindowSize;
		freeWindowRefFn = &X11FreeWindowRef;
		getErrorMessageFn = &X11GetErrorMessage;
	} else {
#endif
		getWindowGeometryFn = &AXUIGetWindowGeometry;
		setWindowPositionFn = &AXUISetWindowPosition;
		setWindowSizeFn = &AXUISetWindowSize;
		freeWindowRefFn = &AXUIFreeWindowRef;
		getErrorMessageFn = &AXUIGetErrorMessage;		
#ifdef X11
	}
#endif
	
	int x = [window originalRect_].origin.x, y = [window originalRect_].origin.x;
	unsigned int width = [window originalRect_].size.width, height = [window originalRect_].size.height;
	
	BOOL useDrawers = [[NSUserDefaults standardUserDefaults] boolForKey:kIncludeDrawersPrefKey];
	
	NSRect windowRect = [window rect_];
	
	FMTDevLog(@"window rect: %@", RECT_STR(windowRect));
		
#ifdef X11
	if ([window x11win_]) {
		// adjust the menu bar:
		// cocoa windows get the size counted from the [0,GetMBarHeight()]
		// whereas X11 gets [0,0] so we need to add it to them
		if ([screen belowPrimary_] || [screen primary]) {
			windowRect.origin.y += GetMBarHeight();
		}
	}
#endif
	
	// screen coordinates of the best fit window
	NSRect screenRect = [screen screenFrame_];
	//	FMTDevLog(@"screen rect (cocoa): %@", RECT_STR(screenRect));	
	COCOA_TO_SCREEN_COORDINATES(screenRect);
	FMTDevLog(@"screen rect: %@", RECT_STR(screenRect));	
	
	// visible screen coordinates of the best fit window
	// the visible screen denotes some inner rect of the screen rect which is visible - not occupied by menu bar or dock
	NSRect visibleScreenRect = [screen visibleFrame_];
	//	FMTDevLog(@"visible screen rect (cocoa): %@", RECT_STR(visibleScreenRect));	
	COCOA_TO_SCREEN_COORDINATES(visibleScreenRect);
	FMTDevLog(@"visible screen rect: %@", RECT_STR(visibleScreenRect));	
	
	// readjust adjust the window rect to be relative of the screen at origin [0,0]
	NSRect relWindowRect = windowRect;
	relWindowRect.origin.x -= visibleScreenRect.origin.x;
	relWindowRect.origin.y -= visibleScreenRect.origin.y;
	FMTDevLog(@"window rect relative to [0,0]: %@", RECT_STR(relWindowRect));	
	
	NSRect shiftedRect = {
		origin,
		size
	};
	FMTDevLog(@"shifted window rect: %@", RECT_STR(shiftedRect));
	
	// drawers
	if (useDrawers) {
		NSRect drawersRect = [window drawersRect_];
		
		if (drawersRect.size.width > 0) {
			if (drawersRect.origin.x < x) {
				shiftedRect.origin.x += x - drawersRect.origin.x;
			}
			if (drawersRect.origin.y < windowRect.origin.y) {
				shiftedRect.origin.y += y - drawersRect.origin.y;
			}
			if (drawersRect.origin.x + drawersRect.size.width > x + width) {
				shiftedRect.size.width -= - (x + width - drawersRect.origin.x) // this is the offset, drawers do not start at the end of the frame
				+ drawersRect.size.width;
			}
			if (drawersRect.origin.y + drawersRect.size.height > y + height) {
				shiftedRect.size.height -= - (y + height - drawersRect.origin.y) // this is the offset, drawers do not start at the end of the frame
				+ drawersRect.size.height;
			}	
			
			FMTDevLog(@"shifted window rect after drawers adjustements: %@", RECT_STR(shiftedRect));
		}
	}
	
	// readjust adjust the visibility
	// the shiftedRect is the new application window geometry relative to the screen originating at [0,0]
	// we need to shift it accordingly that is to the origin of the best fit screen (screenRect) and
	// take into account the visible area of such a screen - menu, dock, etc. which is in the visibleScreenRect
	shiftedRect.origin.x += screenRect.origin.x + visibleScreenRect.origin.x - screenRect.origin.x;
	shiftedRect.origin.y += screenRect.origin.y + visibleScreenRect.origin.y - screenRect.origin.y;// - ([screen isPrimary] ? GetMBarHeight() : 0);
	
	// we need to translate from cocoa coordinates
	FMTDevLog(@"shifted window within screen: %@", RECT_STR(shiftedRect));	
	
	if (!NSEqualRects(windowRect, shiftedRect)) {
		
#ifdef X11
        if ([window x11win_]) {
			NSRect X11CoordRef = [window x11CoordRect_];
            // translate into X11 coordinates
            shiftedRect.origin.x -= X11CoordRef.origin.x;
            shiftedRect.origin.y -= X11CoordRef.origin.y;
			
            // readjust back the menu bar
            if ([screen belowPrimary_] || [screen primary]) {
                shiftedRect.origin.y -= GetMBarHeight();
            }
        } else { 
#endif // X11			
			
#ifdef X11
		}
#endif
		
		FMTDevLog(@"translated shifted rect: %@", RECT_STR(shiftedRect));
		
		x = (int) shiftedRect.origin.x;
		y = (int) shiftedRect.origin.y;
		width = (unsigned int) shiftedRect.size.width;
		height = (unsigned int) shiftedRect.size.height;
		
		int ret = -1;

		// move window
		FMTDevLog(@"moving window to: %dx%d", x, y);		
		if ((ret = setWindowPositionFn([window ref_], x, y)) != 0) {
			*error = CreateError(kUnableToChangeWindowPositionErrorCode, FMTStrc(getErrorMessageFn(ret)), nil);
			return;
		}
		
		// resize window
		FMTDevLog(@"resizing to: %dx%d", width, height);
		if ((ret = setWindowSizeFn([window ref_], width, height)) != 0) {
			*error = CreateError(kUnableToChangeWindowSizeErrorCode, FMTStrc(getErrorMessageFn(ret)), nil);
			return;
		}
		
		// there are apps that does not size continuously but rather discretely so
		// they have to be re-adjusted
		int dx = 0;
		int dy = 0;
		
		// in order to check for the bottom anchor we have to deal with the menu bar again
		// TODO: debug in multiscreen (X11)
		int mbarAdj = 0;
#ifdef X11
		if (![window x11win_]) {
			mbarAdj = GetMBarHeight();
		}
#else
		mbarAdj = GetMBarHeight();
#endif
		
		// get the anchor and readjust the size
		if (x + width == visibleScreenRect.size.width || y + height == visibleScreenRect.size.height + mbarAdj) {
			int unused;
			unsigned int width2,height2; 
			
			// check how was it resized
			if ((ret = getWindowGeometryFn([window ref_], &unused, &unused, &width2, &height2)) != 0) {
				*error = CreateError(kUnableToGetWindowGeometryErrorCode, FMTStrc(getErrorMessageFn(ret)), nil);
				return;
			}
			FMTDevLog(@"window resized to: %dx%d", width2, height2);
			
			// check whether the anchor is at the right part of the screen
			if (x + width == visibleScreenRect.size.width
				&& x > visibleScreenRect.size.width - width - x) {
				dx = width - width2;
			}
			
			// check whether the anchor is at the bottom part of the screen
			if (y + height == visibleScreenRect.size.height + mbarAdj
				&& y - mbarAdj > visibleScreenRect.size.height + mbarAdj - height - y) {
				dy = height - height2;
			}
			
			if (dx != 0 || dy != 0) {
				// there have to be two separate move actions. cocoa window could not be resize over the screen boundaries
				FMTDevLog(@"adjusting by delta: %dx%d", dx, dy);		
				if ((ret = setWindowPositionFn([window ref_], x+dx, y+dy)) != 0) {
					*error = CreateError(kUnableToChangeWindowPositionErrorCode, FMTStrc(getErrorMessageFn(ret)), nil);
					return;
				}		
			}
		}
	} else {
		FMTDevLog(@"Shifted window origin and dimensions are the same");
	}
	
	// 	freeWindowRefFn(window);	

}

/**
 * Chooses the best screen for the given window rect (screen coord).
 *
 * For each screen it computes the intersecting rectangle and its size. 
 * The biggest is the screen where is the most of the window hence the best fit.
 */
- (NSScreen *)chooseScreenForWindow_:(NSRect)windowRect {
	// TODO: rename intgersect
	// TODO: all should be ***Rect
	
	NSScreen *fitScreen = [NSScreen mainScreen];
	float maxSize = 0;
	
	for (NSScreen *screen in [NSScreen screens]) {
		NSRect screenRect = [screen frame];
		// need to convert coordinates
		COCOA_TO_SCREEN_COORDINATES(screenRect);
		
		NSRect intersectRect = NSIntersectionRect(screenRect, windowRect);
		
		if (intersectRect.size.width > 0 ) {
			float size = intersectRect.size.width * intersectRect.size.height;
			if (size > maxSize) {
				fitScreen = screen;
				maxSize = size;
			}
		}
	}
	
	return fitScreen;
}

@end