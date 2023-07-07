import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appDocumentDir = await getApplicationDocumentsDirectory();
  final databasePath = appDocumentDir.path + '/pokemon.db';
  final database = await openDatabase(databasePath, version: 2, onCreate: (db, version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pokemon (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        url TEXT
      )
    ''');
  });

  runApp(PokemonApp(database));
}

class Pokemon {
  late int id;
  late String name;
  late String url;

  Pokemon({required this.id, required this.name, required this.url});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'url': url,
    };
  }

  factory Pokemon.fromMap(Map<String, dynamic> map) {
    return Pokemon(
      id: map['id'],
      name: map['name'],
      url: map['url'],
    );
  }
}

class PokemonApp extends StatelessWidget {
  final Database database;

  PokemonApp(this.database);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pokémon App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: HomePage(database),
    );
  }
}

class HomePage extends StatelessWidget {
  final Database database;

  HomePage(this.database);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Pokemon')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Pokémon',
              style: TextStyle(fontSize: 24),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => PokemonListPage(database)),
                );
              },
              child: Text('Mirar pokemones'),
            ),
          ],
        ),
      ),
    );
  }
}

class PokemonListPage extends StatefulWidget {
  final Database database;

  PokemonListPage(this.database);

  @override
  _PokemonListPageState createState() => _PokemonListPageState();
}

class _PokemonListPageState extends State<PokemonListPage> {
  List<Pokemon> pokemonList = [];
  List<Pokemon> favoritePokemonList = [];
  String searchText = '';

  @override
  void initState() {
    super.initState();
    openPokemonDatabase();
    fetchPokemonList();
  }

  Future<void> openPokemonDatabase() async {
    setState(() {
      pokemonList = [];
    });

    final List<Map<String, dynamic>> maps = await widget.database.query('pokemon');
    final List<Pokemon> pokemonFromDB = List.generate(maps.length, (i) {
      return Pokemon.fromMap(maps[i]);
    });

    setState(() {
      pokemonList = pokemonFromDB;
    });
  }

  Future<void> fetchPokemonList() async {
    final response = await http.get(Uri.parse('https://pokeapi.co/api/v2/pokemon?limit=1000'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic> results = data['results'];

      for (int i = 0; i < results.length; i++) {
        final result = results[i];
        final pokemon = Pokemon(
          id: i + 1, // Assign unique ID based on the index
          name: result['name'],
          url: result['url'],
        );

        // Check if the pokemon is already in the database
        final existingPokemon = await widget.database.query(
          'pokemon',
          where: 'name = ?',
          whereArgs: [pokemon.name],
          limit: 1,
        );

        if (existingPokemon.isEmpty) {
          await widget.database.insert('pokemon', pokemon.toMap());
        }
      }

      openPokemonDatabase();
    }
  }

  void addToFavorites(Pokemon pokemon) {
    setState(() {
      favoritePokemonList.add(pokemon);
    });
  }

  void removeFromFavorites(Pokemon pokemon) {
    setState(() {
      favoritePokemonList.remove(pokemon);
    });
  }

  bool isFavorite(Pokemon pokemon) {
    return favoritePokemonList.contains(pokemon);
  }

  List<Pokemon> getFilteredPokemonList() {
    if (searchText.isEmpty) {
      return pokemonList;
    } else {
      return pokemonList.where((pokemon) => pokemon.name.toLowerCase().contains(searchText)).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredPokemonList = getFilteredPokemonList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Lista de Pokémon'),
        actions: [
          IconButton(
            icon: Icon(Icons.favorite),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => FavoritePokemonPage(favoritePokemonList: favoritePokemonList)),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              onChanged: (text) {
                setState(() {
                  searchText = text.toLowerCase();
                });
              },
              decoration: InputDecoration(
                labelText: 'Buscar Pokémon',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredPokemonList.length,
              itemBuilder: (context, index) {
                final pokemon = filteredPokemonList[index];
                final pokemonNumber = getPokemonNumber(pokemon.url);

                return ListTile(
                  leading: CachedNetworkImage(
                    imageUrl: 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/${pokemonNumber}.png',
                    imageBuilder: (context, imageProvider) => CircleAvatar(
                      backgroundImage: imageProvider,
                      backgroundColor: Colors.transparent,
                    ),
                    placeholder: (context, url) => CircularProgressIndicator(),
                    errorWidget: (context, url, error) => Icon(Icons.error),
                  ),
                  title: Text(pokemon.name),
                  subtitle: FutureBuilder(
                    future: fetchPokemonAbility(pokemon.url),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Text('Loading...');
                      } else if (snapshot.hasError) {
                        return Text('Error');
                      } else {
                        final ability = snapshot.data;
                        return Text(ability!);
                      }
                    },
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      isFavorite(pokemon) ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite(pokemon) ? Colors.red : null,
                    ),
                    onPressed: () {
                      if (isFavorite(pokemon)) {
                        removeFromFavorites(pokemon);
                      } else {
                        addToFavorites(pokemon);
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<String> fetchPokemonAbility(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final abilities = data['abilities'];
      final ability = abilities[0]['ability']['name'];
      return ability;
    } else {
      throw Exception('Failed to fetch ability');
    }
  }

  int getPokemonNumber(String url) {
    final regex = RegExp(r'/(\d+)/$');
    final match = regex.firstMatch(url);
    final numberString = match?.group(1) ?? '';
    return int.tryParse(numberString) ?? 0;
  }
}

class FavoritePokemonPage extends StatefulWidget {
  final List<Pokemon> favoritePokemonList;

  FavoritePokemonPage({required this.favoritePokemonList});

  @override
  _FavoritePokemonPageState createState() => _FavoritePokemonPageState();
}

class _FavoritePokemonPageState extends State<FavoritePokemonPage> {
  void removeFromFavorites(Pokemon pokemon) {
    setState(() {
      widget.favoritePokemonList.remove(pokemon);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredPokemonList = widget.favoritePokemonList;

    return Scaffold(
      appBar: AppBar(title: Text('Pokemones favoritos')),
      body: ListView.builder(
        itemCount: filteredPokemonList.length,
        itemBuilder: (context, index) {
          final pokemon = filteredPokemonList[index];
          final pokemonNumber = getPokemonNumber(pokemon.url);

          return ListTile(
            leading: CachedNetworkImage(
              imageUrl: 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/${pokemonNumber}.png',
              imageBuilder: (context, imageProvider) => CircleAvatar(
                backgroundImage: imageProvider,
                backgroundColor: Colors.transparent,
              ),
              placeholder: (context, url) => CircularProgressIndicator(),
              errorWidget: (context, url, error) => Icon(Icons.error),
            ),
            title: Text(pokemon.name),
            subtitle: FutureBuilder(
              future: fetchPokemonAbility(pokemon.url),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Text('Loading...');
                } else if (snapshot.hasError) {
                  return Text('Error');
                } else {
                  final ability = snapshot.data;
                  return Text(ability!);
                }
              },
            ),
            trailing: IconButton(
              icon: Icon(Icons.delete),
              onPressed: () {
                removeFromFavorites(pokemon);
              },
            ),
          );
        },
      ),
    );
  }

  Future<String> fetchPokemonAbility(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final abilities = data['abilities'];
      final ability = abilities[0]['ability']['name'];
      return ability;
    } else {
      throw Exception('Failed to fetch ability');
    }
  }

  int getPokemonNumber(String url) {
    final regex = RegExp(r'/(\d+)/$');
    final match = regex.firstMatch(url);
    final numberString = match?.group(1) ?? '';
    return int.tryParse(numberString) ?? 0;
  }
}
