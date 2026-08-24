/*
 * Copyright (c) Infinite Monkey Theorem AB
 */

using InfiniteMonkey.Application;

namespace InfiniteMonkey.Infrastructure
{
    public sealed class FixedReferenceTextSource : IReferenceTextSource
    {
        public string GetText()
        {
            return "SpecOps v2 reference architecture";
        }
    }
}
