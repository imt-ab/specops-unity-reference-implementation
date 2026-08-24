/*
 * Copyright (c) Infinite Monkey Theorem AB
 */

using System;
using System.Collections.Generic;
using System.IO;
using NUnit.Framework;
using UnityEditor;
using UnityEditor.Compilation;
using UnityEngine;

namespace InfiniteMonkey.EditModeTests
{
    public class ArchitectureBoundaryTests
    {
        private static readonly RuntimeAssemblyDescriptor[] RuntimeAssemblies =
        {
            new RuntimeAssemblyDescriptor(
                "InfiniteMonkey.Domain",
                "Assets/Project/Code/Runtime/Domain/InfiniteMonkey.Domain.asmdef"),
            new RuntimeAssemblyDescriptor(
                "InfiniteMonkey.Application",
                "Assets/Project/Code/Runtime/Application/InfiniteMonkey.Application.asmdef",
                "InfiniteMonkey.Domain"),
            new RuntimeAssemblyDescriptor(
                "InfiniteMonkey.AI",
                "Assets/Project/Code/Runtime/AI/InfiniteMonkey.AI.asmdef",
                "InfiniteMonkey.Application",
                "InfiniteMonkey.Domain"),
            new RuntimeAssemblyDescriptor(
                "InfiniteMonkey.Infrastructure",
                "Assets/Project/Code/Runtime/Infrastructure/InfiniteMonkey.Infrastructure.asmdef",
                "InfiniteMonkey.Application",
                "InfiniteMonkey.Domain"),
            new RuntimeAssemblyDescriptor(
                "InfiniteMonkey.Presentation",
                "Assets/Project/Code/Runtime/Presentation/InfiniteMonkey.Presentation.asmdef",
                "InfiniteMonkey.Application"),
            new RuntimeAssemblyDescriptor(
                "InfiniteMonkey.Composition",
                "Assets/Project/Code/Runtime/Composition/InfiniteMonkey.Composition.asmdef",
                "InfiniteMonkey.Application",
                "InfiniteMonkey.Domain",
                "InfiniteMonkey.Infrastructure",
                "InfiniteMonkey.Presentation"),
            new RuntimeAssemblyDescriptor(
                "InfiniteMonkey.Utility",
                "Assets/Project/Code/Runtime/Utility/InfiniteMonkey.Utility.asmdef")
        };

        [Test]
        public void DomainAndApplication_KeepNoEngineReferences()
        {
            AssertNoEngineReferences("InfiniteMonkey.Domain");
            AssertNoEngineReferences("InfiniteMonkey.Application");
        }

        [Test]
        public void DomainAndApplication_CompiledAssembliesExcludeUnityReferences()
        {
            var compiledAssemblies = CompilationPipeline.GetAssemblies(
                AssembliesType.PlayerWithoutTestAssemblies);

            AssertCompiledAssemblyExcludesUnityReferences(compiledAssemblies, "InfiniteMonkey.Domain");
            AssertCompiledAssemblyExcludesUnityReferences(compiledAssemblies, "InfiniteMonkey.Application");
        }

        [Test]
        public void RuntimeAsmdefs_ContainOnlyAllowedProjectReferences()
        {
            var definitionsByName = new Dictionary<string, AsmdefDefinition>(StringComparer.Ordinal);
            var projectAssemblyByGuid = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

            foreach (var descriptor in RuntimeAssemblies)
            {
                var definition = ReadAsmdef(descriptor);
                definitionsByName.Add(definition.name, definition);

                var guid = AssetDatabase.AssetPathToGUID(descriptor.AssetPath);
                Assert.That(
                    guid,
                    Is.Not.Empty,
                    $"Runtime assembly '{descriptor.ExpectedName}' has no asset GUID at '{descriptor.AssetPath}'.");
                projectAssemblyByGuid.Add(guid, definition.name);
            }

            foreach (var descriptor in RuntimeAssemblies)
            {
                var definition = definitionsByName[descriptor.ExpectedName];
                foreach (var reference in definition.references)
                {
                    string targetAssembly = null;
                    if (definitionsByName.ContainsKey(reference))
                    {
                        targetAssembly = reference;
                    }
                    else if (reference.StartsWith("GUID:", StringComparison.OrdinalIgnoreCase))
                    {
                        projectAssemblyByGuid.TryGetValue(reference.Substring("GUID:".Length), out targetAssembly);
                    }

                    if (targetAssembly == null)
                    {
                        continue;
                    }

                    Assert.That(
                        descriptor.AllowedTargets,
                        Does.Contain(targetAssembly),
                        $"Runtime assembly '{definition.name}' at '{descriptor.AssetPath}' references prohibited " +
                        $"project assembly '{targetAssembly}'. Allowed project targets: " +
                        $"{FormatAllowedTargets(descriptor.AllowedTargets)}.");
                }
            }
        }

        private static void AssertNoEngineReferences(string assemblyName)
        {
            var descriptor = FindDescriptor(assemblyName);
            var definition = ReadAsmdef(descriptor);

            Assert.That(
                definition.noEngineReferences,
                Is.True,
                $"Assembly '{assemblyName}' at '{descriptor.AssetPath}' must set noEngineReferences=true; " +
                $"actual value: {definition.noEngineReferences}.");
        }

        private static void AssertCompiledAssemblyExcludesUnityReferences(
            UnityEditor.Compilation.Assembly[] compiledAssemblies,
            string assemblyName)
        {
            var compiledAssembly = Array.Find(
                compiledAssemblies,
                candidate => string.Equals(candidate.name, assemblyName, StringComparison.Ordinal));

            Assert.That(
                compiledAssembly,
                Is.Not.Null,
                $"Expected compiled player assembly '{assemblyName}' was absent from " +
                $"CompilationPipeline.GetAssemblies(AssembliesType.PlayerWithoutTestAssemblies).");

            var offendingReferences = new List<string>();
            foreach (var referencePath in compiledAssembly.allReferences)
            {
                var referencedAssembly = Path.GetFileNameWithoutExtension(referencePath);
                if (referencedAssembly.StartsWith("UnityEngine", StringComparison.Ordinal) ||
                    referencedAssembly.StartsWith("UnityEditor", StringComparison.Ordinal))
                {
                    offendingReferences.Add($"{referencedAssembly} ({referencePath})");
                }
            }

            Assert.That(
                offendingReferences,
                Is.Empty,
                $"Compiled assembly '{assemblyName}' at '{compiledAssembly.outputPath}' references Unity " +
                $"assemblies: {string.Join(", ", offendingReferences)}.");
        }

        private static RuntimeAssemblyDescriptor FindDescriptor(string assemblyName)
        {
            var descriptor = Array.Find(
                RuntimeAssemblies,
                candidate => string.Equals(candidate.ExpectedName, assemblyName, StringComparison.Ordinal));

            Assert.That(descriptor, Is.Not.Null, $"No runtime asmdef descriptor exists for '{assemblyName}'.");
            return descriptor;
        }

        private static AsmdefDefinition ReadAsmdef(RuntimeAssemblyDescriptor descriptor)
        {
            var absolutePath = GetAbsoluteProjectPath(descriptor.AssetPath);
            Assert.That(File.Exists(absolutePath), Is.True, $"Runtime asmdef not found: '{descriptor.AssetPath}'.");

            var definition = JsonUtility.FromJson<AsmdefDefinition>(File.ReadAllText(absolutePath));
            Assert.That(definition, Is.Not.Null, $"Runtime asmdef could not be parsed: '{descriptor.AssetPath}'.");
            Assert.That(
                definition.name,
                Is.EqualTo(descriptor.ExpectedName),
                $"Runtime asmdef at '{descriptor.AssetPath}' declared unexpected assembly name '{definition.name}'.");
            Assert.That(
                definition.references,
                Is.Not.Null,
                $"Runtime asmdef '{definition.name}' at '{descriptor.AssetPath}' has no references array.");

            return definition;
        }

        private static string GetAbsoluteProjectPath(string assetPath)
        {
            var projectDirectory = Directory.GetParent(UnityEngine.Application.dataPath);
            Assert.That(projectDirectory, Is.Not.Null, "Unable to resolve the Unity project directory.");
            return Path.GetFullPath(
                Path.Combine(projectDirectory.FullName, assetPath.Replace('/', Path.DirectorySeparatorChar)));
        }

        private static string FormatAllowedTargets(string[] allowedTargets)
        {
            return allowedTargets.Length == 0 ? "<none>" : string.Join(", ", allowedTargets);
        }

        [Serializable]
        private sealed class AsmdefDefinition
        {
            public string name = string.Empty;
            public string[] references = Array.Empty<string>();
            public bool noEngineReferences = false;
        }

        private sealed class RuntimeAssemblyDescriptor
        {
            public RuntimeAssemblyDescriptor(string expectedName, string assetPath, params string[] allowedTargets)
            {
                ExpectedName = expectedName;
                AssetPath = assetPath;
                AllowedTargets = allowedTargets;
            }

            public string ExpectedName { get; }

            public string AssetPath { get; }

            public string[] AllowedTargets { get; }
        }
    }
}
