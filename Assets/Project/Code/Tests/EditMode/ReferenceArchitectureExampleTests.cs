/*
 * Copyright (c) Infinite Monkey Theorem AB
 */

using System;
using InfiniteMonkey.Application;
using InfiniteMonkey.Domain;
using InfiniteMonkey.Infrastructure;
using InfiniteMonkey.Presentation;
using Moq;
using NUnit.Framework;
using UnityEngine;
using Object = UnityEngine.Object;

namespace InfiniteMonkey.EditModeTests
{
    public class ReferenceMessageTests
    {
        [Test]
        public void Constructor_WithValidText_PreservesText()
        {
            const string text = "  SpecOps v2 reference architecture  ";

            var message = new ReferenceMessage(text);

            Assert.That(message.Text, Is.EqualTo(text));
        }

        [Test]
        public void Constructor_WithNull_ThrowsArgumentNullException()
        {
            var exception = Assert.Throws<ArgumentNullException>(() => new ReferenceMessage(null));

            Assert.That(exception.ParamName, Is.EqualTo("text"));
        }

        [Test]
        public void Constructor_WithEmpty_ThrowsArgumentException()
        {
            var exception = Assert.Throws<ArgumentException>(() => new ReferenceMessage(string.Empty));

            Assert.That(exception.ParamName, Is.EqualTo("text"));
        }

        [Test]
        public void Constructor_WithWhitespace_ThrowsArgumentException()
        {
            var exception = Assert.Throws<ArgumentException>(() => new ReferenceMessage("   "));

            Assert.That(exception.ParamName, Is.EqualTo("text"));
        }
    }

    public class CreateReferenceMessageTests
    {
        [Test]
        public void Execute_ObtainsTextAndReturnsAcceptedString()
        {
            const string text = "Controlled reference text";
            var textSource = new Mock<IReferenceTextSource>();
            textSource.Setup(source => source.GetText()).Returns(text);
            var useCase = new CreateReferenceMessage(textSource.Object);

            var result = useCase.Execute();

            Assert.That(result, Is.EqualTo(text));
            textSource.Verify(source => source.GetText(), Times.Once);
        }

        [Test]
        public void Execute_WhenSourceReturnsInvalidText_UsesDomainValidation()
        {
            var textSource = new Mock<IReferenceTextSource>();
            textSource.Setup(source => source.GetText()).Returns("   ");
            var useCase = new CreateReferenceMessage(textSource.Object);

            var exception = Assert.Throws<ArgumentException>(() => useCase.Execute());

            Assert.That(exception.ParamName, Is.EqualTo("text"));
            textSource.Verify(source => source.GetText(), Times.Once);
        }
    }

    public class FixedReferenceTextSourceTests
    {
        [Test]
        public void GetText_ReturnsStableReferenceText()
        {
            const string expected = "SpecOps v2 reference architecture";
            IReferenceTextSource textSource = new FixedReferenceTextSource();

            var first = textSource.GetText();
            var second = textSource.GetText();

            Assert.That(first, Is.EqualTo(expected));
            Assert.That(second, Is.EqualTo(expected));
        }
    }

    public class ReferenceMessagePresenterTests
    {
        [Test]
        public void Present_ForwardsApplicationResult()
        {
            const string expected = "Presentation-safe reference text";
            GameObject gameObject = null;

            try
            {
                gameObject = new GameObject("Reference Message Presenter Test");
                gameObject.SetActive(false);
                var presenter = gameObject.AddComponent<ReferenceMessagePresenter>();
                var textSource = new Mock<IReferenceTextSource>();
                textSource.Setup(source => source.GetText()).Returns(expected);
                presenter.Initialize(new CreateReferenceMessage(textSource.Object));

                var result = presenter.Present();

                Assert.That(result, Is.EqualTo(expected));
                textSource.Verify(source => source.GetText(), Times.Once);
            }
            finally
            {
                if (gameObject != null)
                {
                    Object.DestroyImmediate(gameObject);
                }
            }
        }

        [Test]
        public void Present_BeforeInitialize_ThrowsInvalidOperationException()
        {
            GameObject gameObject = null;

            try
            {
                gameObject = new GameObject("Uninitialized Reference Message Presenter Test");
                gameObject.SetActive(false);
                var presenter = gameObject.AddComponent<ReferenceMessagePresenter>();

                Assert.Throws<InvalidOperationException>(() => presenter.Present());
            }
            finally
            {
                if (gameObject != null)
                {
                    Object.DestroyImmediate(gameObject);
                }
            }
        }
    }
}
