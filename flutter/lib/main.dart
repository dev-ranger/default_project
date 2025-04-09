import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 앱 전체에서 사용되는 상수 정의
class AppConstants {
  // UI 관련 상수
  static const String appTitle = '이미지 예측 앱';
  static const double defaultPadding = 16.0;
  static const double imageDimension = 300.0;
  static const double buttonHeight = 50.0;
  static const double spaceBetweenElements = 20.0;
  static const double resultFontSize = 16.0;

  // 메시지 상수
  static const String noImageSelectedMessage = '이미지가 선택되지 않았습니다';
  static const String selectImageButtonLabel = '이미지 선택';
  static const String predictButtonLabel = '예측 실행';
  static const String serverUrlLabel = '서버 URL 입력';
  static const String loadingMessage = '예측 중...';

  // API 관련 상수
  static const String predictEndpoint = '/predict';
  static const String imageFileParameter = 'file';

  // 에러 메시지
  static const String noImageError = '먼저 이미지를 선택해주세요';
  static const String networkError = '네트워크 오류가 발생했습니다';
  static const String serverError = '서버 오류가 발생했습니다: ';
}

/// 앱의 메인 진입점
void main() async {
  // Flutter 엔진 초기화
  WidgetsFlutterBinding.ensureInitialized();
  // 환경 변수 로드
  await dotenv.load(fileName: ".env.dev");
  // 앱 실행
  runApp(const ImagePredictionApp());
}

/// 앱의 루트 위젯
class ImagePredictionApp extends StatelessWidget {
  const ImagePredictionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appTitle,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: Size(double.infinity, AppConstants.buttonHeight),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
      home: const ImagePredictionPage(),
    );
  }
}

/// 이미지 예측 페이지
class ImagePredictionPage extends StatefulWidget {
  const ImagePredictionPage({super.key});

  @override
  State<ImagePredictionPage> createState() => _ImagePredictionPageState();
}

class _ImagePredictionPageState extends State<ImagePredictionPage> {
  // 상태 변수들
  File? selectedImage;
  String predictionResult = "";
  Map<String, double> predictionMap = {}; // 예측 결과를 저장할 맵 변수 추가
  bool isLoading = false;

  // 컨트롤러 및 서비스
  final TextEditingController serverUrlController = TextEditingController();
  final ImagePicker imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();

    // 환경 변수에서 기본 URL 로드
    final String? baseUrl = dotenv.env['BASE_URL'];
    if (baseUrl != null && baseUrl.isNotEmpty) {
      serverUrlController.text = baseUrl;
    }
  }

  @override
  void dispose() {
    // 컨트롤러 해제
    serverUrlController.dispose();
    super.dispose();
  }

  /// 갤러리에서 이미지 선택
  Future<void> selectImageFromGallery() async {
    try {
      final XFile? pickedImage = await imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80, // 이미지 품질 최적화
      );

      if (pickedImage != null) {
        setState(() {
          selectedImage = File(pickedImage.path);
          // 이미지가 새로 선택되면 이전 예측 결과 초기화
          predictionResult = "";
          predictionMap = {}; // 예측 맵 초기화
        });
      }
    } catch (e) {
      showErrorSnackBar('이미지 선택 중 오류가 발생했습니다: $e');
    }
  }

  /// 선택된 이미지로 예측 수행
  Future<void> performImagePrediction() async {
    // A. 이미지가 선택되지 않은 경우 처리
    if (selectedImage == null) {
      setState(() {
        predictionResult = AppConstants.noImageError;
        predictionMap = {}; // 맵 초기화
      });
      showErrorSnackBar(AppConstants.noImageError);
      return;
    }

    // B. 예측 시작 (로딩 상태 설정)
    setState(() {
      isLoading = true;
      predictionResult = AppConstants.loadingMessage;
      predictionMap = {}; // 맵 초기화
    });

    try {
      final response = await uploadImageAndGetPrediction(
        selectedImage!,
        serverUrlController.text,
      );

      setState(() {
        isLoading = false;
        predictionResult = formatPredictionResults(response);
        predictionMap = extractPredictionMap(response); // 맵으로 결과 추출
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        predictionResult = '오류 발생: $e';
        predictionMap = {}; // 오류 시 맵 비우기
      });
      showErrorSnackBar(e.toString());
    }
  }

  /// 이미지를 서버에 업로드하고 예측 결과 가져오기
  Future<Map<String, dynamic>> uploadImageAndGetPrediction(
      File imageFile,
      String serverUrl,
      ) async {
    try {
      // URL 구성
      final Uri uri = Uri.parse('$serverUrl${AppConstants.predictEndpoint}');

      // 요청 생성
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll({
        'ngrok-skip-browser-warning': '8000',
      });

      // 이미지 파일 추가
      request.files.add(
        await http.MultipartFile.fromPath(
          AppConstants.imageFileParameter,
          imageFile.path,
        ),
      );

      // 요청 전송
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      // 응답 처리
      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
        jsonDecode(response.body) as Map<String, dynamic>;
        return data;
      } else {
        throw Exception('${AppConstants.serverError}${response.statusCode}');
      }
    } catch (e) {
      if (e is SocketException || e is http.ClientException) {
        throw Exception(AppConstants.networkError);
      }
      rethrow;
    }
  }

  /// 예측 결과를 포맷팅
  String formatPredictionResults(Map<String, dynamic> data) {
    try {
      // 'predictions' 키가 있는 경우와 없는 경우를 모두 처리
      Map<String, dynamic> predictions;
      if (data.containsKey('predictions')) {
        predictions = data['predictions'] as Map<String, dynamic>;
      } else {
        // 'predictions' 키가 없으면 응답 자체가 예측 결과임
        predictions = data;
      }

      final sortedEntries = predictions.entries.toList()
        ..sort((a, b) => (b.value as num).compareTo(a.value as num));

      return sortedEntries
          .map((e) => '${e.key}: ${formatProbability(e.value)}')
          .join('\n');
    } catch (e) {
      return '결과 형식 오류: $e';
    }
  }

  /// 예측 결과를 맵으로 추출
  Map<String, double> extractPredictionMap(Map<String, dynamic> data) {
    try {
      Map<String, dynamic> predictions;
      if (data.containsKey('predictions')) {
        predictions = data['predictions'] as Map<String, dynamic>;
      } else {
        predictions = data;
      }

      return predictions.map((key, value) =>
          MapEntry(key, value is double ? value : double.tryParse(value.toString()) ?? 0.0));
    } catch (e) {
      print('예측 맵 추출 오류: $e');
      return {};
    }
  }

  /// 확률 값 포맷팅 (소수점 2자리까지)
  String formatProbability(dynamic value) {
    if (value is double) {
      return (value * 100).toStringAsFixed(2) + '%';
    }
    return value.toString();
  }

  /// 에러 메시지 스낵바 표시
  void showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildImagePreviewCard(),
                const SizedBox(height: AppConstants.spaceBetweenElements),
                _buildServerUrlInput(),
                const SizedBox(height: AppConstants.spaceBetweenElements),
                _buildPredictionButton(),
                const SizedBox(height: AppConstants.spaceBetweenElements),
                _buildResultDisplay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 이미지 미리보기 카드 구성
  Widget _buildImagePreviewCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: AppConstants.imageDimension,
                height: AppConstants.imageDimension,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: selectedImage != null
                    ? Image.file(
                  selectedImage!,
                  fit: BoxFit.cover,
                )
                    : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                          Icons.image_outlined,
                          size: 64,
                          color: Colors.grey.shade400
                      ),
                      const SizedBox(height: 16),
                      Text(
                        AppConstants.noImageSelectedMessage,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: selectImageFromGallery,
              icon: const Icon(Icons.photo_library),
              label: const Text(AppConstants.selectImageButtonLabel),
            ),
          ],
        ),
      ),
    );
  }

  /// 서버 URL 입력 필드 구성
  Widget _buildServerUrlInput() {
    return TextField(
      controller: serverUrlController,
      decoration: InputDecoration(
        labelText: AppConstants.serverUrlLabel,
        prefixIcon: const Icon(Icons.link),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      keyboardType: TextInputType.url,
    );
  }

  /// 예측 실행 버튼 구성
  Widget _buildPredictionButton() {
    return ElevatedButton.icon(
      onPressed: isLoading ? null : performImagePrediction,
      icon: isLoading
          ? const SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      )
          : const Icon(Icons.insights),
      label: Text(
        isLoading
            ? AppConstants.loadingMessage
            : AppConstants.predictButtonLabel,
      ),
    );
  }

  /// 예측 결과 표시 영역 구성
  Widget _buildResultDisplay() {
    // predictionMap이 비어있으면 아무것도 표시하지 않음
    if (predictionMap.isEmpty) {
      return const SizedBox.shrink();
    }

    // 결과를 내림차순으로 정렬 (확률이 높은 것이 먼저 표시)
    final sortedEntries = predictionMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                '예측 결과',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(),
            const SizedBox(height: 8),
            ...sortedEntries.map((entry) => _buildPredictionItem(entry.key, entry.value)),
          ],
        ),
      ),
    );
  }

  /// 개별 예측 항목 위젯
  Widget _buildPredictionItem(String label, double probability) {
    // 확률에 따라 색상 결정 (확률이 높을수록 더 진한 색상)
    final color = HSLColor.fromAHSL(
      1.0,
      220, // 색조(hue) - 파란색 계열
      0.8, // 채도(saturation)
      0.3 + (0.4 * probability), // 명도(lightness) - 확률에 따라 조정
    ).toColor();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(), // 대문자로 표시하여 가독성 향상
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                formatProbability(probability),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: probability,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 12,
            ),
          ),
        ],
      ),
    );
  }
}