/*
 * Copyright (c) Infinite Monkey Theorem AB
 */

using InfiniteMonkey.Composition.LifetimeScopes;
using InfiniteMonkey.Presentation;
using NUnit.Framework;
using UnityEngine;
using Object = UnityEngine.Object;

namespace InfiniteMonkey.EditModeTests
{
    public class ReferenceCompositionTests
    {
        [Test]
        public void LifetimeScope_BuildsAndExecutesCompleteFlowWithoutScene()
        {
            GameObject gameObject = null;
            ReferenceLifetimeScope lifetimeScope = null;

            try
            {
                gameObject = new GameObject("Reference Composition Test");
                gameObject.SetActive(false);
                var presenter = gameObject.AddComponent<ReferenceMessagePresenter>();
                lifetimeScope = gameObject.AddComponent<ReferenceLifetimeScope>();

                lifetimeScope.Build();

                Assert.That(gameObject.activeSelf, Is.False);
                Assert.That(presenter.Present(), Is.EqualTo("SpecOps v2 reference architecture"));
            }
            finally
            {
                if (lifetimeScope != null)
                {
                    lifetimeScope.DisposeCore();
                }

                if (gameObject != null)
                {
                    Object.DestroyImmediate(gameObject);
                }
            }
        }
    }
}
