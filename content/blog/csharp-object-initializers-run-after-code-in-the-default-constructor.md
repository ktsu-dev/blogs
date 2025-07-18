---
title: "C# Object Initializers Run After Code in the Default Constructor"
author: "Matt Edmondson"
created: 2025-06-14
modified: 2025-06-14
status: draft
description: "A deep dive into C# object initialization order, explaining why object initializers run after the default constructor and how to handle this behavior effectively."
categories: ["Development", "C#"]
tags: ["csharp", "object-initializers", "constructors"]
keywords: ["C# object initializers", "constructor execution order", "property initialization", "C# best practices", "object initialization patterns"]
slug: "csharp-object-initializers-run-after-code-in-the-default-constructor"
---

# C# Object Initializers Run After Code in the Default Constructor

When working with C# object initializers, it's crucial to understand their execution order relative to the default constructor. This behavior can sometimes lead to unexpected results if not properly understood.

## The Execution Order

In C#, when you create an object using an object initializer, the following sequence occurs:

1. The default constructor runs first
2. Then, the object initializer properties are set

This means that any code in the default constructor will execute before the properties are initialized through the object initializer syntax.

## Why the Order Matters

Let's look at a practical example to demonstrate this behavior:

```csharp
public class Person
{
    public string Name { get; set; }
    public int Age { get; set; }

    public Person()
    {
        Console.WriteLine("Constructor running...");
        Console.WriteLine($"Name: {Name}, Age: {Age}");
    }
}

// Usage
var person = new Person
{
    Name = "John",
    Age = 30
};
```

When this code runs, the output will be:

```
Constructor running...
Name: null, Age: 0
```

Notice that when the constructor runs, the properties haven't been set yet. The `Name` is null and `Age` is 0, even though we're about to set them in the object initializer.

## Collection Initializers

Collection initializers follow a similar pattern. The collection's constructor runs first, followed by the `Add` calls:

```csharp
var list = new List<int> { 1, 2, 3 };
```

This is equivalent to:

```csharp
var list = new List<int>();
list.Add(1);
list.Add(2);
list.Add(3);
```

> ⚠️ **Important Note**: Be cautious when using collection initializers with custom collections, as the `Add` method may perform validation or trigger side effects. For example, a custom collection might validate each item during `Add`, or a concurrent collection might perform synchronization operations.

## Common Pitfalls

This behavior can lead to some common issues:

1. **Property Validation**: If your constructor validates properties, it might fail because the properties haven't been set yet.

2. **Dependent Properties**: If you have properties that depend on other properties being set, you might get unexpected results.

3. **Event Handlers**: If you wire up events in the constructor that rely on property values, they may not behave as expected because the properties are not yet initialized.

## Safer Patterns

To avoid issues with this execution order, consider these safer patterns:

### 1. Immutable Objects with Parameterized Constructors

The safest approach is to use immutable objects with read-only properties:

```csharp
public class Person
{
    public string Name { get; }
    public int Age { get; }

    public Person(string name, int age)
    {
        Name = name;
        Age = age;
    }
}

// Usage
var person = new Person("John", 30);
```

This pattern ensures:
- All properties are set as part of constructor logic
- Properties cannot be modified after creation
- The object is always in a valid state

### 2. Record Types (C# 9+)

In C# 9 and later, record types offer a concise syntax for immutable objects with value semantics:

```csharp
public record Person(string Name, int Age);

// Usage
var person = new Person("John", 30);

// Records support deconstruction
var (name, age) = person;
```

Records automatically provide:
- Immutable properties
- Value-based equality
- Deconstruction support
- A concise syntax for immutable data

### 3. Factory Methods with Private Constructors

For more complex initialization scenarios, combine factory methods with private constructors:

```csharp
public class Person
{
    public string Name { get; }
    public int Age { get; }

    private Person(string name, int age)
    {
        Name = name;
        Age = age;
    }

    public static Person Create(string name, int age)
    {
        return new Person(name, age);
    }
}

// Usage
var person = Person.Create("John", 30);
```

This pattern provides:
- Complete control over object creation
- Guaranteed immutability
- Centralized creation logic
- No possibility of invalid states

### 4. Builder Pattern

For objects with many optional properties, consider using the Builder pattern:

```csharp
public class PersonBuilder
{
    private string name;
    private int age;

    public PersonBuilder WithName(string name)
    {
        this.name = name;
        return this;
    }

    public PersonBuilder WithAge(int age)
    {
        this.age = age;
        return this;
    }

    public Person Build()
    {
        return new Person(name, age);
    }
}

// Usage
var person = new PersonBuilder()
    .WithName("John")
    .WithAge(30)
    .Build();
```

## Best Practices

1. **Favor Immutability**: Design objects to be fully initialized upon creation and prevent further mutation. This reduces the risk of inconsistent states and makes the code more predictable.

2. **Use Constructor Parameters**: When properties must be set before any logic runs, use constructor parameters rather than object initializers.

3. **Validate Early**: If property validation is crucial, do it in the constructor using parameters rather than relying on object initializers.

4. **Consider Factory Methods**: Use factory methods when you need to centralize creation logic or perform additional setup after property initialization.

5. **Be Aware of Collection Initializers**: Remember that collection initializers follow the same pattern as object initializers, with the constructor running before any `Add` calls take place.

## Under the Hood

The C# compiler transforms object initializers into a sequence of property assignments after the constructor call. That's why constructors always run before property assignments. Here's the IL code generated for our example:

```il
// Create new instance
IL_0000: newobj instance void Person::.ctor()
IL_0005: dup

// Set Name property
IL_0006: ldstr "John"
IL_000B: callvirt instance void Person::set_Name(string)
IL_0010: dup

// Set Age property
IL_0011: ldc.i4.s 30
IL_0013: callvirt instance void Person::set_Age(int32)
```

You can explore this transformation yourself using tools like [SharpLab](https://sharplab.io/) or [.NET Fiddle](https://dotnetfiddle.net/).

## Conclusion

Understanding the execution order of object initializers and constructors is essential for writing reliable C# code. Remember: constructors run first, then property assignments follow. This knowledge will help you avoid common pitfalls and write more predictable code.

For more detailed information, refer to the [Microsoft Docs on Object and Collection Initializers](https://docs.microsoft.com/en-us/dotnet/csharp/programming-guide/classes-and-structs/object-and-collection-initializers).

## References

- [C# Language Specification](https://docs.microsoft.com/en-us/dotnet/csharp/language-reference/language-specification/expressions#object-initializers)
- [C# Object Initializers Documentation](https://docs.microsoft.com/en-us/dotnet/csharp/programming-guide/classes-and-structs/object-and-collection-initializers)
- [C# Collection Initializers Documentation](https://docs.microsoft.com/en-us/dotnet/csharp/programming-guide/classes-and-structs/object-and-collection-initializers#collection-initializers)
- [Factory Method Pattern](https://refactoring.guru/design-patterns/factory-method)
- [Builder Pattern](https://refactoring.guru/design-patterns/builder)
- [Roslyn Compiler Source](https://github.com/dotnet/roslyn/blob/main/src/Compilers/CSharp/Portable/Binder/Binder_Expressions.cs)
- [SharpLab](https://sharplab.io/) - Interactive C# compiler explorer 