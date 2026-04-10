/*
 * Copyright (c) Infinite Monkey Theorem AB
 */

using Moq;
using NUnit.Framework;

namespace InfiniteMonkey.EditModeTests
{
    public interface IFoo
    {
        int Get();
    }

    public class MoqSmokeTest
    {
        [Test]
        public void Can_mock_interface()
        {
            var m = new Mock<IFoo>();
            m.Setup(x => x.Get()).Returns(42);
            Assert.AreEqual(42, m.Object.Get());
        }
    }
}