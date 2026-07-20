//
//  DedicatedWebWallpaperHostCompatibilityScript+Bootstrap.swift
//  MyWallpaperX
//

let webCompatibilityScriptBootstrap = #"""
(() => {
"""#
+ webCompatibilityScriptScheduling
+ "\n"
+ webCompatibilityScriptBootstrapFoundation
+ "\n"
+ webCompatibilityScriptBootstrapPlugins
+ "\n"
+ webCompatibilityScriptBootstrapResourceRewriting
