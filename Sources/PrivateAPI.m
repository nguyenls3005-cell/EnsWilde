//
//  PrivateAPI.m
//  EnsWilde
//
//  Created by Duy Tran on 12/12/25.
//

#import "EnsWilde-Bridging-Header.h"
#include "bad_query.h"

LSApplicationWorkspace *LSApplicationWorkspaceDefaultWorkspace(void) {
    return [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
}