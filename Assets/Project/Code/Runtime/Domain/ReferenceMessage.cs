/*
 * Copyright (c) Infinite Monkey Theorem AB
 */

using System;

namespace InfiniteMonkey.Domain
{
    public sealed class ReferenceMessage
    {
        public ReferenceMessage(string text)
        {
            if (text == null)
            {
                throw new ArgumentNullException(nameof(text));
            }

            if (string.IsNullOrWhiteSpace(text))
            {
                throw new ArgumentException("Value cannot be empty or whitespace.", nameof(text));
            }

            Text = text;
        }

        public string Text { get; }
    }
}
