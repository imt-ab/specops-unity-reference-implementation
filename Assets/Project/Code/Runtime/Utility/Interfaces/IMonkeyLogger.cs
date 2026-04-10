/*
 * Copyright (c) Infinite Monkey Theorem AB
 */

namespace InfiniteMonkey.Utility.Interfaces
{
    public interface IMonkeyLogger
    {
        void Log(string message);
        void LogWarning(string message);
        void LogError(string message);
    }
}