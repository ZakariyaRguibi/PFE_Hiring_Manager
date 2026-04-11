@IsTest
private class HelloWorldTest {
  @IsTest
  static void testGreet() {
    String result = HelloWorld.greet();
    System.assertEquals(
      'Hello, World!',
      result,
      'greet() should return Hello, World!'
    );
  }

  @IsTest
  static void testGreetByName() {
    String result = HelloWorld.greetByName('Alice');
    System.assertEquals(
      'Hello, Alice!',
      result,
      'greetByName() should return Hello, Alice!'
    );
  }

  @IsTest
  static void testGreetByNameThrowsOnBlank() {
    try {
      HelloWorld.greetByName('');
      System.assert(false, 'Expected HelloWorldException was not thrown');
    } catch (HelloWorld.HelloWorldException e) {
      System.assertEquals('Name must not be null or blank.', e.getMessage());
    }
  }

  @IsTest
  static void testGreetInLanguageFrench() {
    String result = HelloWorld.greetInLanguage('fr');
    System.assertEquals('Bonjour, le Monde!', result);
  }

  @IsTest
  static void testGreetInLanguageArabic() {
    String result = HelloWorld.greetInLanguage('ar');
    System.assertEquals('مرحباً بالعالم!', result);
  }

  @IsTest
  static void testGreetInLanguageFallback() {
    String result = HelloWorld.greetInLanguage('zz');
    System.assertEquals('Hello, World!', result);
  }

  @IsTest
  static void testGreetAll() {
    List<String> names = new List<String>{ 'Alice', 'Bob', '', null };
    List<String> results = HelloWorld.greetAll(names);
    System.assertEquals(
      2,
      results.size(),
      'Should skip blank and null entries'
    );
    System.assertEquals('Hello, Alice!', results[0]);
    System.assertEquals('Hello, Bob!', results[1]);
  }

  @IsTest
  static void testGreetAllNullInput() {
    List<String> results = HelloWorld.greetAll(null);
    System.assertEquals(
      0,
      results.size(),
      'Null input should return empty list'
    );
  }
}
