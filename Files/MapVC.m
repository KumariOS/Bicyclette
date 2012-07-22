//
//  MapVC.m
//  Bicyclette
//
//  Created by Nicolas on 04/12/10.
//  Copyright 2010 Nicolas Bouilleaud. All rights reserved.
//

#import "MapVC.h"
#import "BicycletteApplicationDelegate.h"
#import "VelibModel.h"
#import "Station.h"
#import "Region.h"
#import "TransparentToolbar.h"
#import "NSArrayAdditions.h"
#import "RegionAnnotationView.h"
#import "StationAnnotationView.h"
#import "DrawingCache.h"
#import "Radar.h"
#import "RadarAnnotationView.h"
#import "RadarUpdateQueue.h"
#import "MKMapView+GoogleLogo.h"

typedef enum {
	MapLevelNone = 0,
	MapLevelRegions,
	MapLevelRegionsAndRadars,
	MapLevelStationsAndRadars
}  MapLevel;

@interface MapVC() <MKMapViewDelegate>
// UI
@property MKMapView * mapView;
@property RadarAnnotationView * screenCenterRadarView;
@property UIToolbar * mapVCToolbar; // Do not use the system toolbal to prevent its height from changing
@property MKUserTrackingBarButtonItem * userTrackingButton;
@property UISegmentedControl * modeControl;
// Data
@property MKCoordinateRegion referenceRegion;
@property (nonatomic) MapLevel level;
@property (nonatomic) StationAnnotationMode stationMode;

// Radar creation
@property (nonatomic) Radar * droppedRadar;
@end


/****************************************************************************/
#pragma mark -

@implementation MapVC 
{
    DrawingCache * _drawingCache;
}

- (void) awakeFromNib
{
    [super awakeFromNib];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(modelUpdated:)
                                                 name:VelibModelNotifications.updateSucceeded object:nil];
        
    _drawingCache = [DrawingCache new];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

/****************************************************************************/
#pragma mark Loading

- (BOOL) canBecomeFirstResponder
{
    return YES;
}

- (void) loadView
{
    [super loadView]; // get a base view
    
    // Create mapview
    self.mapView = [[MKMapView alloc]initWithFrame:[[UIScreen mainScreen] applicationFrame]];
    [self.view addSubview:self.mapView ];
    self.mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.mapView.showsUserLocation = YES;
    self.mapView.zoomEnabled = YES;
    self.mapView.scrollEnabled = YES;
    self.mapView.delegate = self;
        
    // Add Screen Center Radar View
    self.screenCenterRadarView = [[RadarAnnotationView alloc] initWithAnnotation:self.model.screenCenterRadar drawingCache:_drawingCache];
    [self.view addSubview:self.screenCenterRadarView];
    self.screenCenterRadarView.center = self.mapView.center;
    self.screenCenterRadarView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.screenCenterRadarView.userInteractionEnabled = NO;
    
    // Add gesture recognizer for menu
    UIGestureRecognizer * longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(addRadar:)];
    [self.mapView addGestureRecognizer:longPressRecognizer];

    // prepare toolbar items
    self.userTrackingButton = [[MKUserTrackingBarButtonItem alloc] initWithMapView:self.mapView];
    
    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[ NSLocalizedString(@"BIKE", nil), NSLocalizedString(@"PARKING", nil) ]];
    self.modeControl.segmentedControlStyle = UISegmentedControlStyleBar;
    [self.modeControl addTarget:self action:@selector(switchMode:) forControlEvents:UIControlEventValueChanged];
    self.modeControl.selectedSegmentIndex = self.stationMode;
    UIBarButtonItem * modeItem = [[UIBarButtonItem alloc] initWithCustomView:self.modeControl];
    modeItem.width = 160;
    
    // create toolbar
#define kToolbarHeight 44 // Strange that I have to declare it
    self.mapVCToolbar = [[TransparentToolbar alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height-kToolbarHeight, self.view.bounds.size.width, kToolbarHeight)];
    [self.view addSubview:self.mapVCToolbar];
    self.mapVCToolbar.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    self.mapVCToolbar.items = @[self.userTrackingButton,
    [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
    modeItem,
    [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil]];
    
    // observe changes to the prefs
    [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:@"RadarDistance" options:0 context:(__bridge void *)([MapVC class])];

    // Forget old userLocation, until we have a better one
    [self.model userLocationRadar].coordinate = CLLocationCoordinate2DMake(0, 0);

    // reload data
    [self reloadData];
}

- (void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    // Relocate google logo
    self.mapView.googleLogo.frame = (CGRect){CGPointZero,self.mapView.googleLogo.frame.size};
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    // Relocate google logo
    self.mapView.googleLogo.frame = (CGRect){CGPointZero,self.mapView.googleLogo.frame.size};
}

- (void) reloadData
{
    MKCoordinateRegion region = [self.mapView regionThatFits:self.model.regionContainingData];
    region.span.latitudeDelta /= 2;
    region.span.longitudeDelta /= 2;
    self.referenceRegion = region;

	self.mapView.region = self.referenceRegion;

    [self addAndRemoveMapAnnotations];
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
    return YES;
}

/****************************************************************************/
#pragma mark MapView Delegate

- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated
{
    MKCoordinateRegion viewRegion = self.mapView.region;
    CLLocation * northLocation = [[CLLocation alloc] initWithLatitude:viewRegion.center.latitude+viewRegion.span.latitudeDelta longitude:viewRegion.center.latitude];
    CLLocation * southLocation = [[CLLocation alloc] initWithLatitude:viewRegion.center.latitude-viewRegion.span.latitudeDelta longitude:viewRegion.center.latitude];
    CLLocationDistance distance = [northLocation distanceFromLocation:southLocation];

	if(distance > [[NSUserDefaults standardUserDefaults] doubleForKey:@"MapLevelRegions"])
		self.level = MapLevelNone;
	else if(distance > [[NSUserDefaults standardUserDefaults] doubleForKey:@"MapLevelRegionsAndRadars"])
		self.level = MapLevelRegions;
    else if(distance > [[NSUserDefaults standardUserDefaults] doubleForKey:@"MapLevelStationsAndRadars"])
		self.level = MapLevelRegionsAndRadars;
	else
		self.level = MapLevelStationsAndRadars;
    
    self.screenCenterRadarView.hidden = (self.level!=MapLevelStationsAndRadars);
    
    [self addAndRemoveMapAnnotations];
    [self updateRadarSizes];

    self.model.screenCenterRadar.coordinate = [self.mapView convertPoint:self.screenCenterRadarView.center toCoordinateFromView:self.screenCenterRadarView.superview];
    if(self.level==MapLevelRegionsAndRadars || self.level==MapLevelStationsAndRadars)
        self.model.updaterQueue.referenceLocation = [[CLLocation alloc] initWithLatitude:self.mapView.centerCoordinate.latitude longitude:self.mapView.centerCoordinate.longitude];
    else
        self.model.updaterQueue.referenceLocation = nil;
}


- (MKAnnotationView *)mapView:(MKMapView *)mapView_ viewForAnnotation:(id <MKAnnotation>)annotation
{
	if(annotation == self.mapView.userLocation)
		return nil;
	else if([annotation isKindOfClass:[Region class]])
	{
		RegionAnnotationView * regionAV = (RegionAnnotationView*)[self.mapView dequeueReusableAnnotationViewWithIdentifier:[RegionAnnotationView reuseIdentifier]];
		if(nil==regionAV)
			regionAV = [[RegionAnnotationView alloc] initWithAnnotation:annotation drawingCache:_drawingCache];

        return regionAV;
	}
	else if([annotation isKindOfClass:[Station class]])
	{
		StationAnnotationView * stationAV = (StationAnnotationView*)[self.mapView dequeueReusableAnnotationViewWithIdentifier:[StationAnnotationView reuseIdentifier]];
		if(nil==stationAV)
			stationAV = [[StationAnnotationView alloc] initWithAnnotation:annotation drawingCache:_drawingCache];

        stationAV.mode = self.stationMode;
		return stationAV;
	}
    else if([annotation isKindOfClass:[Radar class]])
    {
        RadarAnnotationView * radarAV = (RadarAnnotationView*)[self.mapView dequeueReusableAnnotationViewWithIdentifier:[RadarAnnotationView reuseIdentifier]];
		if(nil==radarAV)
			radarAV = [[RadarAnnotationView alloc] initWithAnnotation:annotation drawingCache:_drawingCache];
        
        CGSize radarSize = [self.mapView convertRegion:((Radar*)annotation).radarRegion toRectToView:self.mapView].size;
        radarAV.bounds = (CGRect){CGPointZero, radarSize};

        return radarAV;
    }
	return nil;
}

- (void)mapView:(MKMapView *)mapView didSelectAnnotationView:(MKAnnotationView *)view
{
	if([view.annotation isKindOfClass:[Region class]])
		[self zoomInRegion:(Region*)view.annotation];
    else if([view.annotation isKindOfClass:[Station class]])
        [self refreshStation:(Station*)view.annotation]; 
}

- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view didChangeDragState:(MKAnnotationViewDragState)newState
fromOldState:(MKAnnotationViewDragState)oldState
{
    if([view.annotation isKindOfClass:[Radar class]])
    {
        [self.mapView selectAnnotation:view.annotation animated:YES];
        if(newState==MKAnnotationViewDragStateCanceling)
            [self showRadarMenu:(Radar*)view.annotation];
    }

}

- (void)mapView:(MKMapView *)mapView didUpdateUserLocation:(MKUserLocation *)userLocation
{
    [self.model userLocationRadar].coordinate = userLocation.coordinate;
}

- (void) addAndRemoveMapAnnotations
{
    NSArray * oldAnnotations = self.mapView.annotations;
    oldAnnotations = [oldAnnotations arrayByRemovingObjectsInArray:@[ self.mapView.userLocation ]];
    NSMutableArray * newAnnotations = [NSMutableArray new];

    if (self.level == MapLevelNone)
    {
        // Model
        [newAnnotations addObject:self.model];
    }

    if (self.level == MapLevelRegions || self.level == MapLevelRegionsAndRadars)
    {
        // Regions
        NSFetchRequest * regionsRequest = [NSFetchRequest new];
        regionsRequest.entity = [Region entityInManagedObjectContext:self.model.moc];
        [newAnnotations addObjectsFromArray:[self.model.moc executeFetchRequest:regionsRequest error:NULL]];
    }
    
    if (self.level == MapLevelRegionsAndRadars || self.level == MapLevelStationsAndRadars)
    {
        // Radars
        NSFetchRequest * radarsRequest = [NSFetchRequest new];
        [radarsRequest setEntity:[Radar entityInManagedObjectContext:self.model.moc]];
        NSMutableArray * allRadars = [[self.model.moc executeFetchRequest:radarsRequest error:NULL] mutableCopy];
        // do not add an annotation for screenCenterRadar, it's handled separately.
        [allRadars removeObject:self.model.screenCenterRadar];
        // only add the userLocationRadar if it's actually here
        if(self.mapView.userLocation.coordinate.latitude==0.0)
            [allRadars removeObject:self.model.userLocationRadar];
        [newAnnotations addObjectsFromArray:[newAnnotations arrayByAddingObjectsFromArray:allRadars]];
    }

    if (self.level == MapLevelStationsAndRadars)
    {
        // Stations
        NSFetchRequest * stationsRequest = [NSFetchRequest new];
		[stationsRequest setEntity:[Station entityInManagedObjectContext:self.model.moc]];
        MKCoordinateRegion mapRegion = self.mapView.region;
		stationsRequest.predicate = [NSPredicate predicateWithFormat:@"latitude>%f AND latitude<%f AND longitude>%f AND longitude<%f",
							 mapRegion.center.latitude - mapRegion.span.latitudeDelta/2,
                             mapRegion.center.latitude + mapRegion.span.latitudeDelta/2,
                             mapRegion.center.longitude - mapRegion.span.longitudeDelta/2,
                             mapRegion.center.longitude + mapRegion.span.longitudeDelta/2];
        [newAnnotations addObjectsFromArray:[self.model.moc executeFetchRequest:stationsRequest error:NULL]];
    }

    NSArray * annotationsToRemove = [oldAnnotations arrayByRemovingObjectsInArray:newAnnotations];
    NSArray * annotationsToAdd = [newAnnotations arrayByRemovingObjectsInArray:oldAnnotations];
    
    [self.mapView removeAnnotations:annotationsToRemove];
    [self.mapView addAnnotations:annotationsToAdd];
}

- (void) updateRadarSizes
{
    for (Radar * radar in self.mapView.annotations)
    {
        if([radar isKindOfClass:[Radar class]])
        {
            CGSize radarSize = [self.mapView convertRegion:radar.radarRegion toRectToView:self.mapView].size;
            [self.mapView viewForAnnotation:radar].bounds = (CGRect){CGPointZero, radarSize};
        }
    }
    CGSize radarSize = [self.mapView convertRegion:self.model.screenCenterRadar.radarRegion toRectToView:self.mapView].size;
    self.screenCenterRadarView.bounds = (CGRect){CGPointZero, radarSize};
}

/****************************************************************************/
#pragma mark Actions

- (void) addRadar:(UILongPressGestureRecognizer*)longPressRecognizer
{
    switch (longPressRecognizer.state)
    {
        case UIGestureRecognizerStatePossible:
            break;
            
        case UIGestureRecognizerStateBegan:
            self.droppedRadar = [Radar insertInManagedObjectContext:self.model.moc];
            [self.mapView addAnnotation:self.droppedRadar];
            self.droppedRadar.coordinate = [self.mapView convertPoint:[longPressRecognizer locationInView:self.mapView]
                                                 toCoordinateFromView:self.mapView];
            [self performSelector:@selector(selectDroppedRadar) withObject:nil afterDelay:.2]; // Strangely, the mapview does not return the annotation view before a delay
            break;
        case UIGestureRecognizerStateChanged:
            self.droppedRadar.coordinate = [self.mapView convertPoint:[longPressRecognizer locationInView:self.mapView]
                                                 toCoordinateFromView:self.mapView];
            break;
        case UIGestureRecognizerStateEnded:
            [[self.mapView viewForAnnotation:self.droppedRadar] setDragState:MKAnnotationViewDragStateEnding animated:YES];
            break;
            
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            [self.mapView removeAnnotation:self.droppedRadar];
            [self.model.moc deleteObject:self.droppedRadar];
            self.droppedRadar = nil;
            break;
    }
}

- (void) selectDroppedRadar
{
    [self.mapView selectAnnotation:self.droppedRadar animated:YES];
    [[self.mapView viewForAnnotation:self.droppedRadar] setDragState:MKAnnotationViewDragStateStarting animated:YES];
}

- (void) refreshStation:(Station*)station
{
    [station refresh];
}

- (void) zoomInRegion:(Region*)region
{
    MKCoordinateRegion cregion = [self.mapView regionThatFits:region.coordinateRegion];
    CLLocationDistance meters = [[NSUserDefaults standardUserDefaults] doubleForKey:@"MapRegionZoomDistance"];
    cregion = MKCoordinateRegionMakeWithDistance(cregion.center, meters, meters);
	[self.mapView setRegion:cregion animated:YES];
}

- (void) showRadarMenu:(Radar*)radar
{
    [self becomeFirstResponder];
    UIMenuController * menu = [UIMenuController sharedMenuController];
    
    CGPoint point = [self.mapView convertCoordinate:radar.coordinate toPointToView:self.mapView];
    [menu setTargetRect:(CGRect){point,CGSizeZero} inView:self.mapView];
    [menu setMenuVisible:YES animated:YES];
}

- (void) delete:(id)sender // From UIMenuController
{
    for (Radar * radar in self.mapView.selectedAnnotations)
    {
        if([radar isKindOfClass:[Radar class]])
        {
            [self.mapView removeAnnotation:radar];
            [self.model.moc deleteObject:radar];
        }
    }
}

- (void) switchMode:(UISegmentedControl*)sender
{
    self.stationMode = sender.selectedSegmentIndex;

    for (id<MKAnnotation> annotation in self.mapView.annotations) {
        StationAnnotationView * stationAV = (StationAnnotationView*)[self.mapView viewForAnnotation:annotation];
        if([stationAV isKindOfClass:[StationAnnotationView class]])
            stationAV.mode = self.stationMode;
    }
}

/****************************************************************************/
#pragma mark -

- (void) setAnnotationsHidden:(BOOL)hidden
{
    for (id annotation in self.mapView.annotations) 
        [self.mapView viewForAnnotation:annotation].hidden = hidden;
}

/****************************************************************************/
#pragma mark -

- (void) modelUpdated:(NSNotification*) note
{
    if([note.userInfo[VelibModelNotifications.keys.dataChanged] boolValue])
        [self reloadData];
}

/****************************************************************************/
#pragma mark -

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == (__bridge void *)([MapVC class])) {
        if(object == [NSUserDefaults standardUserDefaults] && [keyPath isEqualToString:@"RadarDistance"])
            [self updateRadarSizes];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end
