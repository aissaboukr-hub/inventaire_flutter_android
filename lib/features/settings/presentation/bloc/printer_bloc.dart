import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/repositories/printer_repository.dart';
import 'printer_event.dart';
import 'printer_state.dart';

class PrinterBloc extends Bloc<PrinterEvent, PrinterState> {
  final PrinterRepository repository;

  PrinterBloc({required this.repository}) : super(const PrinterState()) {
    on<InitPrinterEvent>(_onInit);
    on<RefreshPrinterEvent>(_onRefresh);
    on<ScanPrintersEvent>(_onScan);
    on<ConnectPrinterEvent>(_onConnect);
    on<DisconnectPrinterEvent>(_onDisconnect);
    on<TestPrintEvent>(_onTestPrint);
  }

  Future<void> _onInit(InitPrinterEvent event, Emitter<PrinterState> emit) async {
    final mac = repository.getSavedPrinterMac();
    final name = repository.getSavedPrinterName();
    emit(state.copyWith(
      status: mac == null ? PrinterStatus.initial : PrinterStatus.connecting,
      connectedMac: mac,
      connectedName: name,
      clearError: true,
    ));
    if (mac == null || mac.trim().isEmpty) return;

    try {
      // Reconnexion directe à l'imprimante mémorisée : aucun scan Bluetooth au démarrage.
      final success = await repository.reconnectSavedPrinter(mac);
      if (success) {
        emit(state.copyWith(status: PrinterStatus.connected, connectedMac: mac, connectedName: name, clearError: true));
      } else {
        // L'échec au démarrage ne bloque pas l'application : l'utilisateur pourra relancer
        // une recherche depuis les paramètres pour une nouvelle imprimante.
        emit(state.copyWith(status: PrinterStatus.disconnected, clearError: true));
      }
    } catch (_) {
      emit(state.copyWith(status: PrinterStatus.disconnected, clearError: true));
    }
  }

  Future<void> _onRefresh(
      RefreshPrinterEvent event, Emitter<PrinterState> emit) async {
    final savedMac = repository.getSavedPrinterMac();
    final savedName = repository.getSavedPrinterName();
    emit(state.copyWith(status: PrinterStatus.connecting, clearError: true, connectedMac: savedMac, connectedName: savedName));

    // Le bouton Actualiser tente d'abord la reconnexion directe.
    if (savedMac != null && savedMac.trim().isNotEmpty) {
      try {
        if (await repository.reconnectSavedPrinter(savedMac)) {
          emit(state.copyWith(status: PrinterStatus.connected, connectedMac: savedMac, connectedName: savedName, clearError: true));
          return;
        }
      } catch (_) {}
    }

    // Seulement si l'imprimante mémorisée est indisponible, on effectue le scan complet.
    try {
      emit(state.copyWith(status: PrinterStatus.scanning, clearError: true));
      final devices = await repository.scanDevices();
      if (devices.isEmpty) {
        emit(state.copyWith(status: PrinterStatus.scanFailure, errorMessage: 'Aucun appareil Bluetooth appairé trouvé.', devices: []));
        return;
      }

      for (final device in devices) {
        final success = await repository.connect(device.macAdress);
        if (success) {
          await repository.savePrinterData(device.macAdress, device.name);
          emit(state.copyWith(status: PrinterStatus.connected, connectedMac: device.macAdress, connectedName: device.name, devices: devices, clearError: true));
          return;
        }
      }
      emit(state.copyWith(status: PrinterStatus.scanFailure, errorMessage: 'Impossible de connecter une imprimante.', devices: devices));
    } catch (e) {
      emit(state.copyWith(status: PrinterStatus.scanFailure, errorMessage: e.toString()));
    }
  }

  Future<void> _onScan(
      ScanPrintersEvent event, Emitter<PrinterState> emit) async {
    emit(state.copyWith(status: PrinterStatus.scanning, clearError: true));
    try {
      final devices = await repository.scanDevices();
      emit(state.copyWith(
        status: PrinterStatus.scanSuccess,
        devices: devices,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: PrinterStatus.scanFailure,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onConnect(
      ConnectPrinterEvent event, Emitter<PrinterState> emit) async {
    emit(state.copyWith(status: PrinterStatus.connecting, clearError: true));
    final success = await repository.connect(event.mac);
    if (success) {
      await repository.savePrinterData(event.mac, event.name);
      emit(state.copyWith(
        status: PrinterStatus.connected,
        connectedMac: event.mac,
        connectedName: event.name,
      ));
    } else {
      emit(state.copyWith(
        status: PrinterStatus.connectionFailure,
        errorMessage: 'Impossible de connecter l’imprimante',
      ));
    }
  }

  Future<void> _onDisconnect(
      DisconnectPrinterEvent event, Emitter<PrinterState> emit) async {
    await repository.disconnect();
    await repository.clearPrinterData();
    emit(PrinterState(
      status: PrinterStatus.disconnected,
      devices: state.devices,
    ));
  }

  Future<void> _onTestPrint(
      TestPrintEvent event, Emitter<PrinterState> emit) async {
    emit(state.copyWith(status: PrinterStatus.testPrinting));
    await repository.testPrint(event.shopName);
    emit(state.copyWith(status: PrinterStatus.scanSuccess));
  }
}
