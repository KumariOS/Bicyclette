//
//  BicycletteCities.m
//  Bicyclette
//
//  Created by Nicolas on 12/12/12.
//  Copyright (c) 2012 Nicolas Bouilleaud. All rights reserved.
//

#import "BicycletteCities.h"
#import "CyclocityCities.h"
#import "MarseilleLeVeloCity.h"
#import "ParisVelibCity.h"
#import "LyonVelovCity.h"
#import "OrleansVeloPlusCity.h"
#import "RennesVeloStarCity.h"
#import "MontrealBixiCity.h"

NSArray * BicycletteCityClasses(void)
{
    return @[
             [AmiensVelamCity class],
             [BesanconVelociteCity class],
             [BrisbaneCityCycleCity class],
             [BruxellesVilloCity class],
             [CergyPointoiseVelO2City class],
    		 [CreteilCristoLibCity class],
             [DublinBikesCity class],
             [GoteborgStyrStallCity class],
             [LjubljanaBicikeljCity class],
             [LuxembourgVelohCity class],
    		 [MulhouseVelociteCity class],
			 [NancyVelostanCity class],
             [NantesBiclooCity class],
    		 [RouenCyclicCity class],
             [SantanderTusBicCity class],
             [SevillaSEViciCity class],
             [ToulouseVeloCity class],
             [ToyamaCyclOcityCity class],
             [ValenciaValenbisiCity class],

             [ParisVelibCity class],
             [MarseilleLeVeloCity class],

             [LyonVelovCity class],
             
             [OrleansVeloPlusCity class],
             
             [RennesVeloStarCity class],
             
             [MontrealBixiCity class],
             ];
}
