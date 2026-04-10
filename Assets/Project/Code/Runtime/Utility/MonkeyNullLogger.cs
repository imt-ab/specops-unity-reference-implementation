/*
 * Copyright (c) Infinite Monkey Theorem AB
 */

using InfiniteMonkey.Utility.Interfaces;
using UnityEngine;

namespace InfiniteMonkey.Utility
{
    // ReSharper disable once ClassNeverInstantiated.Global
    public class MonkeyNullLogger : IMonkeyLogger
    {
        public void Log(string message)
        {

        }
        public void LogWarning(string message)
        {

        }
        public void LogError(string message)
        {
            // Log error so that Sentry can catch them
            Debug.LogError(message);
        }
    }
}