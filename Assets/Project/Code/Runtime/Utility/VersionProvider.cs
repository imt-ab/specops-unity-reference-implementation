/*
 * Copyright (c) Infinite Monkey Theorem AB
 */

using InfiniteMonkey.Utility.Interfaces;
using JetBrains.Annotations;
using UnityEngine;

namespace InfiniteMonkey.Utility
{

    [UsedImplicitly]
    public class VersionProvider : IVersionProvider
    {
        public (int major, int minor, int build) GetVersionNumbers()
        {
            string[] parts = Application.version.Split('.');
            int major = parts.Length > 0 ? int.Parse(parts[0]) : 0;
            int minor = parts.Length > 1 ? int.Parse(parts[1]) : 0;
            int build = parts.Length > 2 ? int.Parse(parts[2]) : 0;
            return (major, minor, build);
        }

        public string GetVersionString()
        {
            return Application.version;
        }

        public string GetVersion()
        {
            var (major, minor, build) = GetVersionNumbers();
            return $"{major}.{minor}.{build}";
        }

        public string GetCopyright()
        {
            return $"© {System.DateTime.Now.Year} {Application.companyName} {Application.productName}";
        }
    }
}