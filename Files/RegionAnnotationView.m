//
//  RegionAnnotationView.m
//  Bicyclette
//
//  Created by Nicolas Bouilleaud on 22/06/12.
//  Copyright (c) 2012 Nicolas Bouilleaud. All rights reserved.
//

#import "RegionAnnotationView.h"
#import "DrawingCache.h"
#import "Style.h"


/****************************************************************************/
#pragma mark -

@implementation RegionAnnotationView
{
    DrawingCache * _drawingCache;
}

- (id) initWithRegion:(Region*)region drawingCache:(DrawingCache*)drawingCache
{
    self = [super initWithAnnotation:region reuseIdentifier:[[self class] reuseIdentifier]];
    _drawingCache = drawingCache;
    self.frame = (CGRect){CGPointZero,{kAnnotationViewSize,kAnnotationViewSize}};
    return self;
}

+ (NSString*) reuseIdentifier
{
    return NSStringFromClass([RegionAnnotationView class]);
}

- (Region*) region
{
    return (Region*)self.annotation;
}

- (void) setAnnotation:(id<MKAnnotation>)annotation
{
    
    [self.region removeObserver:self forKeyPath:RegionAttributes.number];
    [super setAnnotation:annotation];
    [self setNeedsDisplay];
    [self.region addObserver:self forKeyPath:RegionAttributes.number options:0 context:(__bridge void *)([RegionAnnotationView class])];
}

- (void) prepareForReuse
{
    [super prepareForReuse];
    [self.region removeObserver:self forKeyPath:RegionAttributes.number];
}

- (BOOL) isOpaque
{
    return NO;
}

- (void) drawRect:(CGRect)rect
{
    CGContextRef c = UIGraphicsGetCurrentContext();

    CGImageRef background = [_drawingCache sharedAnnotationViewBackgroundLayerWithSize:CGSizeMake(kAnnotationViewSize, kAnnotationViewSize)
                                                                                    scale:self.layer.contentsScale
                                                                                    shape:BackgroundShapeRectangle
                                                                               borderMode:BorderModeSolid
                                                                                baseColor:kRegionColor
                                                                                    value:@""
                                                                                    phase:0];

    
    CGContextDrawImage(c, rect, background);

    {
        NSString * text = [[self region] number];
        NSString * line1 = [text substringToIndex:2];
        NSString * line2 = [text substringFromIndex:2];

        CGRect rect1, rect2;
        CGRectDivide(CGRectInset(rect, 0, 4), &rect1, &rect2, 10, CGRectMinYEdge);

        [kAnnotationTitleTextColor setFill];
        CGContextSetShadowWithColor(c, CGSizeMake(0, .5), 0, [kAnnotationTitleShadowColor CGColor]);
        [line1 drawInRect:rect1 withFont:kAnnotationTitleFont lineBreakMode:NSLineBreakByWordWrapping alignment:NSTextAlignmentCenter];

        [kAnnotationDetailTextColor setFill];
        CGContextSetShadowWithColor(c, CGSizeMake(0, .5), 0, [kAnnotationDetailShadowColor CGColor]);
        [line2 drawInRect:rect2 withFont:kAnnotationDetailFont lineBreakMode:NSLineBreakByWordWrapping alignment:NSTextAlignmentCenter];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == (__bridge void *)([RegionAnnotationView class])) {
        [self setNeedsDisplay];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end

/****************************************************************************/
#pragma mark -

@implementation Region (Mapkit) 

- (CLLocationCoordinate2D) coordinate
{
	return self.coordinateRegion.center;
}

@end