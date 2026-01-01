import 'dart:typed_data';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:convert/convert.dart';

void main() {
  runApp(const AssetRegistryApp());
}

class AssetRegistryApp extends StatelessWidget {
  const AssetRegistryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Asset Registry DApp',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AssetRegistryHome(),
    );
  }
}

class AssetRegistryHome extends StatefulWidget {
  const AssetRegistryHome({super.key});

  @override
  State<AssetRegistryHome> createState() => _AssetRegistryHomeState();
}

class _AssetRegistryHomeState extends State<AssetRegistryHome> {
  // ============================================
  // BLOCKCHAIN CONFIGURATION
  // ============================================

  static const String contractAddress = '0xfbBa0e600522eecF536905Bc4EF57c202c2e0E6E';
  static const String rpcUrl = 'https://ethereum-sepolia-rpc.publicnode.com';
  static const int chainId = 11155111;

  static const String contractABI = '''[
	{
		"inputs": [
			{
				"internalType": "bytes32",
				"name": "assetHash",
				"type": "bytes32"
			},
			{
				"internalType": "address",
				"name": "existingOwner",
				"type": "address"
			}
		],
		"name": "AssetAlreadyRegistered",
		"type": "error"
	},
	{
		"inputs": [],
		"name": "InvalidAssetHash",
		"type": "error"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "address",
				"name": "owner",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "bytes32",
				"name": "assetHash",
				"type": "bytes32"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "timestamp",
				"type": "uint256"
			}
		],
		"name": "AssetRegistered",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "address",
				"name": "attemptedBy",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "bytes32",
				"name": "assetHash",
				"type": "bytes32"
			}
		],
		"name": "DuplicateAssetAttempt",
		"type": "event"
	},
	{
		"inputs": [
			{
				"internalType": "bytes32",
				"name": "assetHash",
				"type": "bytes32"
			}
		],
		"name": "getAssetOwner",
		"outputs": [
			{
				"internalType": "address",
				"name": "owner",
				"type": "address"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "getTotalAssets",
		"outputs": [
			{
				"internalType": "uint256",
				"name": "",
				"type": "uint256"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes32",
				"name": "assetHash",
				"type": "bytes32"
			}
		],
		"name": "isAssetRegistered",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "owner",
				"type": "address"
			},
			{
				"internalType": "bytes32",
				"name": "assetHash",
				"type": "bytes32"
			}
		],
		"name": "isOwnerOfAsset",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes32",
				"name": "assetHash",
				"type": "bytes32"
			}
		],
		"name": "registerAsset",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "totalAssetsRegistered",
		"outputs": [
			{
				"internalType": "uint256",
				"name": "",
				"type": "uint256"
			}
		],
		"stateMutability": "view",
		"type": "function"
	}
]''';

  // ============================================
  // STATE VARIABLES
  // ============================================

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  late Web3Client _web3client;
  Credentials? _credentials;
  EthereumAddress? _walletAddress;
  DeployedContract? _contract;
  ContractFunction? _registerAssetFunction;
  ContractFunction? _getAssetOwnerFunction;
  ContractFunction? _isAssetRegisteredFunction;
  ContractFunction? _getTotalAssetsFunction;

  bool _isInitialized = false;
  bool _isLoading = false;
  String _statusMessage = 'Initializing...';
  String? _selectedFilePath;
  String? _selectedFileName;
  String? _currentAssetHash;
  int _totalAssets = 0;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  // ============================================
  // INITIALIZATION FUNCTIONS
  // ============================================

  Future<void> _initializeApp() async {
    try {
      setState(() {
        _statusMessage = 'Connecting to Sepolia testnet...';
      });

      _web3client = Web3Client(rpcUrl, Client());

      setState(() {
        _statusMessage = 'Loading wallet...';
      });

      await _loadOrCreateWallet();

      setState(() {
        _statusMessage = 'Initializing smart contract...';
      });

      await _initializeContract();

      await _loadTotalAssets();

      setState(() {
        _isInitialized = true;
        _statusMessage = 'Ready! Select a file to register.';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Initialization error: ${e.toString()}';
      });
    }
  }

  Future<void> _loadOrCreateWallet() async {
    try {
      String? privateKeyHex = await _secureStorage.read(key: 'eth_private_key');

      if (privateKeyHex != null && privateKeyHex.isNotEmpty) {
        _credentials = EthPrivateKey.fromHex(privateKeyHex);
        _walletAddress = await _credentials!.extractAddress();
        setState(() {
          _statusMessage = 'Wallet loaded successfully';
        });
      } else {
        await _createNewWallet();
      }
    } catch (e) {
      await _createNewWallet();
    }
  }

  Future<void> _createNewWallet() async {
    final random = EthPrivateKey.createRandom(Random.secure());
    _credentials = random;
    _walletAddress = await _credentials!.extractAddress();

    await _secureStorage.write(
      key: 'eth_private_key',
      value: hex.encode((random as EthPrivateKey).privateKey),
    );

    setState(() {
      _statusMessage = 'New wallet created and saved securely';
    });
  }

  Future<void> _initializeContract() async {
    final contract = DeployedContract(
      ContractAbi.fromJson(contractABI, 'AssetRegistry'),
      EthereumAddress.fromHex(contractAddress),
    );

    _contract = contract;

    _registerAssetFunction = contract.function('registerAsset');
    _getAssetOwnerFunction = contract.function('getAssetOwner');
    _isAssetRegisteredFunction = contract.function('isAssetRegistered');
    _getTotalAssetsFunction = contract.function('getTotalAssets');
  }

  Future<void> _loadTotalAssets() async {
    try {
      final result = await _web3client.call(
        contract: _contract!,
        function: _getTotalAssetsFunction!,
        params: [],
      );

      setState(() {
        _totalAssets = (result[0] as BigInt).toInt();
      });
    } catch (e) {
      print('Error loading total assets: $e');
    }
  }

  // ============================================
  // FILE SELECTION & HASHING
  // ============================================

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFilePath = result.files.single.path;
          _selectedFileName = result.files.single.name;
          _currentAssetHash = null;
          _statusMessage = 'File selected: $_selectedFileName';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error picking file: ${e.toString()}';
      });
    }
  }

  Future<String?> _hashFile(String filePath) async {
    try {
      File file = File(filePath);
      Uint8List fileBytes = await file.readAsBytes();
      Digest sha256Hash = sha256.convert(fileBytes);
      String hashHex = sha256Hash.toString();
      return hashHex;
    } catch (e) {
      print('Error hashing file: $e');
      return null;
    }
  }

  // ============================================
  // BLOCKCHAIN INTERACTIONS
  // ============================================

  Future<void> _registerAsset() async {
    if (_selectedFilePath == null) {
      setState(() {
        _statusMessage = 'Please select a file first';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Hashing file...';
    });

    try {
      String? hashHex = await _hashFile(_selectedFilePath!);

      if (hashHex == null) {
        throw Exception('Failed to hash file');
      }

      setState(() {
        _currentAssetHash = hashHex;
        _statusMessage = 'Hash generated: ${hashHex.substring(0, 16)}...';
      });

      Uint8List hashBytes = Uint8List.fromList(
        List<int>.generate(32, (i) =>
            int.parse(hashHex.substring(i * 2, i * 2 + 2), radix: 16)),
      );

      setState(() {
        _statusMessage = 'Checking if asset exists...';
      });

      final isRegistered = await _checkIfAssetRegistered(hashBytes);

      if (isRegistered) {
        final owner = await _getAssetOwner(hashBytes);
        setState(() {
          _isLoading = false;
          _statusMessage = 'Asset already registered by: ${owner.hex}';
        });
        return;
      }

      setState(() {
        _statusMessage = 'Creating transaction...';
      });

      final transaction = Transaction.callContract(
        contract: _contract!,
        function: _registerAssetFunction!,
        parameters: [hashBytes],
      );

      setState(() {
        _statusMessage = 'Sending transaction to blockchain...';
      });

      final txHash = await _web3client.sendTransaction(
        _credentials!,
        transaction,
        chainId: chainId,
      );

      setState(() {
        _statusMessage =
            'Transaction sent! Hash: ${txHash.substring(0, 20)}...\nWaiting for confirmation...';
      });

      TransactionReceipt? receipt;
      int attempts = 0;

      while (receipt == null && attempts < 30) {
        await Future.delayed(const Duration(seconds: 2));
        try {
          receipt = await _web3client.getTransactionReceipt(txHash);
        } catch (_) {}
        attempts++;
        if (attempts % 5 == 0) {
          setState(() {
            _statusMessage =
                'Still waiting for confirmation... (${attempts * 2}s)';
          });
        }
      }

      if (receipt != null) {
        if (receipt.status == true) {
          await _loadTotalAssets();
          setState(() {
            _statusMessage =
                '✅ Asset registered successfully!\nBlock: ${receipt?.blockNumber}\nHash: $hashHex';
          });
        } else {
          setState(() {
            _statusMessage = '❌ Transaction failed!';
          });
        }
      } else {
        setState(() {
          _statusMessage = '⏱️ Transaction timeout. Check Etherscan later.';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<bool> _checkIfAssetRegistered(Uint8List hashBytes) async {
    try {
      final result = await _web3client.call(
        contract: _contract!,
        function: _isAssetRegisteredFunction!,
        params: [hashBytes],
      );
      return result[0] as bool;
    } catch (e) {
      print('Error checking asset: $e');
      return false;
    }
  }

  Future<EthereumAddress> _getAssetOwner(Uint8List hashBytes) async {
    try {
      final result = await _web3client.call(
        contract: _contract!,
        function: _getAssetOwnerFunction!,
        params: [hashBytes],
      );
      return result[0] as EthereumAddress;
    } catch (e) {
      print('Error getting owner: $e');
      return EthereumAddress.fromHex('0x0000000000000000000000000000000000000000');
    }
  }

  Future<void> _checkAssetOwnership() async {
    if (_selectedFilePath == null) {
      setState(() {
        _statusMessage = 'Please select a file first';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Checking asset ownership...';
    });

    try {
      String? hashHex = await _hashFile(_selectedFilePath!);

      if (hashHex == null) throw Exception('Failed to hash file');

      setState(() {
        _currentAssetHash = hashHex;
      });

      Uint8List hashBytes = Uint8List.fromList(
        List<int>.generate(32, (i) =>
            int.parse(hashHex.substring(i * 2, i * 2 + 2), radix: 16)),
      );

      final isRegistered = await _checkIfAssetRegistered(hashBytes);

      if (isRegistered) {
        final owner = await _getAssetOwner(hashBytes);
        bool isMyAsset =
            owner.hex.toLowerCase() == _walletAddress!.hex.toLowerCase();

        setState(() {
          _statusMessage = isMyAsset
              ? '✅ You own this asset!\nHash: $hashHex'
              : '❌ Asset registered by:\n${owner.hex}';
        });
      } else {
        setState(() {
          _statusMessage = 'ℹ️ Asset not registered yet\nHash: $hashHex';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ============================================
  // UI BUILD
  // ============================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asset Registry DApp'),
        centerTitle: true,
        elevation: 0,
      ),
      body: !_isInitialized
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 50,
                    height: 50,
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                      strokeWidth: 4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(_statusMessage),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildWalletCard(),
                  const SizedBox(height: 20),
                  _buildStatsCard(),
                  const SizedBox(height: 20),
                  _buildFileSelectionCard(),
                  const SizedBox(height: 20),
                  _buildActionButtons(),
                  const SizedBox(height: 20),
                  _buildStatusCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildWalletCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Your Wallet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              _walletAddress?.hex ?? 'Wallet not loaded',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(Icons.storage, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text(
              'Total Assets Registered:',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(width: 8),
            Text(
              '$_totalAssets',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileSelectionCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selected File:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedFileName ?? 'No file selected',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.attach_file),
              label: const Text('Select File'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : _registerAsset,
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.upload),
            label: const Text('Register Asset'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : _checkAssetOwnership,
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.search),
            label: const Text('Check Ownership'),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    return Card(
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          _statusMessage,
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }
}
