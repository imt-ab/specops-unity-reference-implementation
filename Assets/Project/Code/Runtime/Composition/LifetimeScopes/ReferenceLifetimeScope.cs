/*
 * Copyright (c) Infinite Monkey Theorem AB
 */

using System;
using InfiniteMonkey.Application;
using InfiniteMonkey.Infrastructure;
using InfiniteMonkey.Presentation;
using VContainer;
using VContainer.Unity;

namespace InfiniteMonkey.Composition.LifetimeScopes
{
    public sealed class ReferenceLifetimeScope : LifetimeScope
    {
        protected override void Configure(IContainerBuilder builder)
        {
            var presenter = GetComponent<ReferenceMessagePresenter>();
            if (presenter == null)
            {
                throw new InvalidOperationException(
                    $"{nameof(ReferenceLifetimeScope)} requires a {nameof(ReferenceMessagePresenter)} on the same GameObject.");
            }

            builder.Register<IReferenceTextSource, FixedReferenceTextSource>(Lifetime.Singleton);
            builder.Register<CreateReferenceMessage>(Lifetime.Singleton);
            builder.RegisterComponent(presenter);
            builder.RegisterBuildCallback(
                resolver => presenter.Initialize(resolver.Resolve<CreateReferenceMessage>()));
        }
    }
}
