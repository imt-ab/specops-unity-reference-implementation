/*
 * Copyright (c) Infinite Monkey Theorem AB
 */

using System;
using InfiniteMonkey.Domain;

namespace InfiniteMonkey.Application
{
    public sealed class CreateReferenceMessage
    {
        private readonly IReferenceTextSource textSource;

        public CreateReferenceMessage(IReferenceTextSource textSource)
        {
            this.textSource = textSource ?? throw new ArgumentNullException(nameof(textSource));
        }

        public string Execute()
        {
            string text = textSource.GetText();
            var referenceMessage = new ReferenceMessage(text);
            return referenceMessage.Text;
        }
    }
}
