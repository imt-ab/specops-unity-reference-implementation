/*
 * Copyright (c) Infinite Monkey Theorem AB
 */

using UnityEngine;
using InfiniteMonkey.Utility.Interfaces;

namespace InfiniteMonkey.Utility
{
    // ReSharper disable once ClassNeverInstantiated.Global
    public class MonkeyDebugLogger : IMonkeyLogger
    {
        public void Log(string message)
        {
            Debug.Log(message);

        }
        public void LogWarning(string message)
        {
            Debug.LogWarning(message);

        }
        public void LogError(string message)
        {
            Debug.LogError(message);

        }
    }
}