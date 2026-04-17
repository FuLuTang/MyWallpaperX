//
//  DedicatedWebWallpaperHostCompatibilityScript+Bootstrap.swift
//  MyWallpaperX
//

let webCompatibilityScriptBootstrap = #"""
(() => {
"""#
+ webCompatibilityScriptBootstrapFoundation
+ "\n"
+ webCompatibilityScriptBootstrapPlugins
+ "\n"
+ webCompatibilityScriptBootstrapResourceRewriting
