using System;
using System.Collections.Generic;
using System.Linq;
using UnityEditor;

namespace Rendering.KageRP.Editor
{
    public static class TypeCacheUtility
    {
        public static List<Type> GetTypes<T>()
        {
            return TypeCache
                .GetTypesDerivedFrom<T>()
                .Where(t =>
                    !t.IsAbstract &&
                    !t.IsInterface &&
                    !t.IsGenericType)
                .OrderBy(t => t.Name)
                .ToList();
        }
    }
}
