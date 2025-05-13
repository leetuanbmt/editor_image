# The following aspects are considered to ensure good quality and high-performance deliverables

### Check list review

##### 1. Requirements

- [ ] 1.1 Task requirements have been met

##### 2. Compiler

- [ ] 2.1 Code compiles without any warnings
- [ ] 2.2 Static analysis passes
- [ ] 2.3 Favorite IDE shows 0 errors, warnings
- [ ] 2.4 No spelling mistakes, except for specific project names or 3rd party packages

##### 3. Naming conventions

- [ ] 3.1 Classes, enums, typedef, and extensions name are in UpperCamelCase
- [ ] 3.2 Libraries, packages, directories, and source files name are in snake_case(lowercase_with_underscores)
- [ ] 3.3 Variables, constants, parameters, and named parameters are in lowerCamelCase
- [ ] 3.4 Semantically meaningful naming approach followed

##### 4. Readability

- [ ] 4.1 Code is self-explanatory
- [ ] 4.2 Controllers, Views, ViewModels, and Repositories do not contain business logic
- [ ] 4.3 There aren't multiple if/else blocks in blocks
- [ ] 4.4 There isn't hardcoded data
- [ ] 4.5 There isn't any commented-out code
- [ ] 4.6 The data flow is understandable
- [ ] 4.7 Streams, TextEditingControllers, and Listeners are closed
- [ ] 4.8 Comments start at /// and contain a clear explanation of method properties, returns, and usage.
- [ ] 4.9 Code does not contain print() log()...
- [ ] 4.10 Reusable code extracted into mixins, utils, and extensions.
- [ ] 4.11 Only private Widgets can be placed in the same file as the parent widget.
- [ ] 4.12 Used const in Widgets
- [ ] 4.13 Switch Case blocs contain the default value
- [ ] 4.14 Code fit in the standard 14-inch laptop screen. There shouldn't be a need to scroll horizontally to view the code

##### 5. Directory structure

- [ ] 5.1 Segregation of code into a proper folder structure namely providers, entities, screens/pages, and utils.

##### 6. Linting rules

- [ ] 6.1 Used package imports
- [ ] 6.2 Used flutter_lints for lint rules

##### 7. Layout

- [ ] 7.1 Widgets do not contain hardcoded sizes
- [ ] 7.2 Widgets do not contain hardcoded colors or font sizes.
- [ ] 7.3 Widgets do not produce render errors

##### 8. State

- [ ] 8.1 Bloc Provider used only at the needed level instead of providing everything at top level
- [ ] 8.2 context.watch() used only when listening to changes
- [ ] 8.3 used context select to listen to specific object properties in order to avoid rebuilding the entire tree

##### 9. Third-party packages

- [ ] 9.1 Used third-party services do not break the build.

##### 10. Implementation

- [ ] 10.1 Code follows Object-Oriented Analysis and Design Principles
- [ ] 10.2 Any use case in which the code does not behave as intended
- [ ] 10.3 DRY
- [ ] 10.4 KISS
- [ ] 10.5 YAGNI
- [ ] 10.6 The Single-responsibility principle followed
- [ ] 10.7 The Open–closed principle followed
- [ ] 10.8 The LisKov substitution principle followed
- [ ] 10.9 The Interface segregation principle followed
- [ ] 10.10 The Dependency inversion principle followed

##### 11. Error handling

- [ ] 11.1 Network requests wrapped into a try .. catch blocks
- [ ] 11.2 Exceptions messages are localized
- [ ] 11.3 Error messages are user-friendly

##### 12. Security and Data Privacy

- [ ] 12.1 Application dependencies are up to date
- [ ] 12.2 Authorization and authentication are handled in the right way
- [ ] 12.3 Sensitive data like user data, and credit card information are securely handled and stored.
- [ ] 12.4 Environment variables aren't stored in git

##### 13. Performance

- [ ] 13.1 Code changes do not impact the system performance in a negative way
