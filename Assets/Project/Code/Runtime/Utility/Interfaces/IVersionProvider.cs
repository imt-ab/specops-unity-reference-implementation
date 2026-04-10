/*
 * Copyright (c) Infinite Monkey Theorem AB
 */

namespace InfiniteMonkey.Utility.Interfaces
{
    public interface IVersionProvider
    {
        (int major, int minor, int build) GetVersionNumbers();
        string GetVersionString();
        string GetVersion();
        string GetCopyright();
    }
}