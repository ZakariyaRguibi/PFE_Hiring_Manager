/**
 * @description A simple demonstration class used to validate the CI/CD pipeline.
 *
 * Provides a set of utility greeting methods that exercise different
 * parameter types and return values so that ApexDocs can generate
 * a rich API reference page for testing purposes.
 *
 * @author Zakariya Rguibi
 * @since 0.1.0
 * @group Utilities
 * @see HelloWorldException
 */
public with sharing class HelloWorld {
  /** @description Default greeting language when none is specified. */
  public static final String DEFAULT_LANGUAGE = 'en';

  /**
   * @description Returns a generic `Hello, World!` greeting.
   *
   * This is the simplest entry point to the class and requires no input.
   * It is primarily used to verify that the class is deployed and callable.
   *
   * @example
   * String msg = HelloWorld.greet();
   * System.debug(msg); // Hello, World!
   *
   * @return A plain `Hello, World!` string.
   */
  public static String greet() {
    return 'Hello, World!';
  }

  /**
   * @description Returns a personalised greeting for the given name.
   *
   * The name is inserted directly into the greeting string.
   * Passing a blank or null name returns the generic greeting instead.
   *
   * @example
   * String msg = HelloWorld.greetByName('Alice');
   * System.debug(msg); // Hello, Alice!
   *
   * @param name The name of the person to greet. Must not be null or blank.
   * @return A greeting string in the form `Hello, <name>!`.
   * @throws HelloWorldException if `name` is null or blank.
   */
  public static String greetByName(String name) {
    if (String.isBlank(name)) {
      throw new HelloWorldException('Name must not be null or blank.');
    }
    return 'Hello, ' + name + '!';
  }

  /**
   * @description Returns a greeting in the requested language.
   *
   * Supported language codes:
   * | Code  | Language | Example output       |
   * |-------|----------|----------------------|
   * | `en`  | English  | Hello, World!        |
   * | `fr`  | French   | Bonjour, le Monde!   |
   * | `ar`  | Arabic   | مرحباً بالعالم!      |
   *
   * Unsupported codes fall back to English.
   *
   * @example
   * String msg = HelloWorld.greetInLanguage('fr');
   * System.debug(msg); // Bonjour, le Monde!
   *
   * @param languageCode An ISO 639-1 two-letter language code (e.g. `'en'`, `'fr'`).
   * @return A localised greeting string.
   */
  public static String greetInLanguage(String languageCode) {
    if (languageCode == 'fr') {
      return 'Bonjour, le Monde!';
    } else if (languageCode == 'ar') {
      return 'مرحباً بالعالم!';
    }
    return greet();
  }

  /**
   * @description Builds a greeting for every name in the provided list.
   *
   * Iterates over the supplied list and calls `greetByName` for each entry.
   * Null or blank entries are skipped silently.
   *
   * @example
   * List<String> names = new List<String>{ 'Alice', 'Bob' };
   * List<String> greetings = HelloWorld.greetAll(names);
   * // ['Hello, Alice!', 'Hello, Bob!']
   *
   * @param names A list of names to greet. Null or blank entries are ignored.
   * @return A list of greeting strings, one per valid name.
   */
  public static List<String> greetAll(List<String> names) {
    List<String> results = new List<String>();
    if (names == null) {
      return results;
    }
    for (String name : names) {
      if (!String.isBlank(name)) {
        results.add(greetByName(name));
      }
    }
    return results;
  }

  /**
   * @description Custom exception thrown when invalid input is supplied to greeting methods.
   *
   * @example
   * try {
   *   HelloWorld.greetByName(null);
   * } catch (HelloWorld.HelloWorldException e) {
   *   System.debug(e.getMessage());
   * }
   */
  public class HelloWorldException extends Exception {
  }
}
