/*
 * Copyright (c) Infinite Monkey Theorem AB
 */

using System;
using InfiniteMonkey.Application;
using UnityEngine;

namespace InfiniteMonkey.Presentation
{
    public sealed class ReferenceMessagePresenter : MonoBehaviour
    {
        private CreateReferenceMessage createReferenceMessage;

        public void Initialize(CreateReferenceMessage createReferenceMessage)
        {
            this.createReferenceMessage = createReferenceMessage ??
                                          throw new ArgumentNullException(nameof(createReferenceMessage));
        }

        public string Present()
        {
            if (createReferenceMessage == null)
            {
                throw new InvalidOperationException("The presenter must be initialized before presenting a message.");
            }

            return createReferenceMessage.Execute();
        }
    }
}
