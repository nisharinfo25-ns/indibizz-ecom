import '../json.dart';

// ---------------------------------------------------------------------------
// Identity and catalogue
// ---------------------------------------------------------------------------
class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    required this.role,
    required this.status,
    this.phone,
    this.email,
    this.createdAt,
  });

  final String id;
  final String fullName;
  final String role;
  final String status;
  final String? phone;
  final String? email;
  final DateTime? createdAt;

  bool get isOwner => role == 'OWNER';
  bool get isDeliveryStaff => const {'OWN_DELIVERY_STAFF', 'PARTNER_ADMIN', 'PARTNER_DELIVERY_STAFF'}.contains(role);
  bool get isPartnerAdmin => role == 'PARTNER_ADMIN';
  bool get isCustomer => role == 'CUSTOMER';
  bool get isActive => status == 'ACTIVE';

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: asString(json['id']),
        fullName: asString(json['full_name'], 'IndiaBizz customer'),
        role: asString(json['role'], 'CUSTOMER'),
        status: asString(json['status'], 'ACTIVE'),
        phone: asNullableString(json['phone']),
        email: asNullableString(json['email']),
        createdAt: asDate(json['created_at']),
      );
}

class CatalogProduct {
  const CatalogProduct({
    required this.id,
    required this.name,
    required this.slug,
    required this.categoryId,
    required this.categoryName,
    required this.categorySlug,
    required this.sku,
    required this.pricePaise,
    required this.isFeatured,
    required this.availableQuantity,
    required this.inStock,
    this.description,
    this.compareAtPricePaise,
    this.taxRateBps = 0,
    this.hsnCode,
    this.weightGrams,
    this.primaryImagePath,
    this.createdAt,
  });

  final String id;
  final String name;
  final String slug;
  final String categoryId;
  final String categoryName;
  final String categorySlug;
  final String sku;
  final int pricePaise;
  final int? compareAtPricePaise;
  final int taxRateBps;
  final String? hsnCode;
  final int? weightGrams;
  final bool isFeatured;
  final int availableQuantity;
  final bool inStock;
  final String? primaryImagePath;
  final String? description;
  final DateTime? createdAt;

  bool get hasDiscount => compareAtPricePaise != null && compareAtPricePaise! > pricePaise;
  int get discountPercent => hasDiscount ? (((compareAtPricePaise! - pricePaise) / compareAtPricePaise!) * 100).round() : 0;

  factory CatalogProduct.fromJson(Map<String, dynamic> json) => CatalogProduct(
        id: asString(json['id']),
        name: asString(json['name'], 'Product'),
        slug: asString(json['slug']),
        categoryId: asString(json['category_id']),
        categoryName: asString(json['category_name'], 'Catalogue'),
        categorySlug: asString(json['category_slug']),
        sku: asString(json['sku']),
        pricePaise: asInt(json['price_paise']),
        compareAtPricePaise: asNullableInt(json['compare_at_price_paise']),
        taxRateBps: asInt(json['tax_rate_bps']),
        hsnCode: asNullableString(json['hsn_code']),
        weightGrams: asNullableInt(json['weight_grams']),
        isFeatured: asBool(json['is_featured']),
        availableQuantity: asInt(json['available_quantity']),
        inStock: asBool(json['in_stock'], asInt(json['available_quantity']) > 0),
        primaryImagePath: asNullableString(json['primary_image_path']),
        description: asNullableString(json['description']),
        createdAt: asDate(json['created_at']),
      );
}

class ProductImage {
  const ProductImage({
    required this.id,
    required this.storagePath,
    this.altText = '',
    this.isPrimary = false,
    this.isPublic = true,
    this.sortOrder = 0,
  });

  final String id;
  final String storagePath;
  final String altText;
  final bool isPrimary;
  final bool isPublic;
  final int sortOrder;

  factory ProductImage.fromJson(Map<String, dynamic> json) => ProductImage(
        id: asString(json['id']),
        storagePath: asString(json['storage_path']),
        altText: asString(json['alt_text']),
        isPrimary: asBool(json['is_primary']),
        isPublic: asBool(json['is_public'], true),
        sortOrder: asInt(json['sort_order']),
      );
}

class AdminProduct {
  const AdminProduct({
    required this.id,
    required this.name,
    required this.slug,
    required this.sku,
    required this.categoryId,
    required this.categoryName,
    required this.pricePaise,
    required this.status,
    required this.quantityOnHand,
    required this.quantityReserved,
    required this.availableQuantity,
    required this.lowStockThreshold,
    required this.isLowStock,
    required this.isFeatured,
    required this.images,
    this.description = '',
    this.compareAtPricePaise,
    this.taxRateBps = 0,
    this.hsnCode,
    this.weightGrams = 0,
    this.createdAt,
  });

  final String id;
  final String name;
  final String slug;
  final String sku;
  final String categoryId;
  final String categoryName;
  final int pricePaise;
  final int? compareAtPricePaise;
  final int taxRateBps;
  final String? hsnCode;
  final int weightGrams;
  final String status;
  final bool isFeatured;
  final int quantityOnHand;
  final int quantityReserved;
  final int availableQuantity;
  final int lowStockThreshold;
  final bool isLowStock;
  final String description;
  final List<ProductImage> images;
  final DateTime? createdAt;

  factory AdminProduct.fromJson(Map<String, dynamic> json) => AdminProduct(
        id: asString(json['id']),
        name: asString(json['name']),
        slug: asString(json['slug']),
        sku: asString(json['sku']),
        categoryId: asString(json['category_id']),
        categoryName: asString(json['category_name']),
        pricePaise: asInt(json['price_paise']),
        compareAtPricePaise: asNullableInt(json['compare_at_price_paise']),
        taxRateBps: asInt(json['tax_rate_bps']),
        hsnCode: asNullableString(json['hsn_code']),
        weightGrams: asInt(json['weight_grams']),
        status: asString(json['status'], 'DRAFT'),
        isFeatured: asBool(json['is_featured']),
        description: asString(json['description']),
        quantityOnHand: asInt(json['quantity_on_hand']),
        quantityReserved: asInt(json['quantity_reserved']),
        availableQuantity: asInt(json['available_quantity']),
        lowStockThreshold: asInt(json['low_stock_threshold'], 5),
        isLowStock: asBool(json['is_low_stock']),
        images: mapJsonList(json['images'], ProductImage.fromJson),
        createdAt: asDate(json['created_at']),
      );
}

class CategoryInfo {
  const CategoryInfo({
    required this.id,
    required this.name,
    required this.slug,
    required this.productCount,
    this.description = '',
    this.imagePath,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String slug;
  final int productCount;
  final String description;
  final String? imagePath;
  final int sortOrder;
  final bool isActive;

  factory CategoryInfo.fromJson(Map<String, dynamic> json) => CategoryInfo(
        id: asString(json['id']),
        name: asString(json['name']),
        slug: asString(json['slug']),
        productCount: asInt(json['product_count']),
        description: asString(json['description']),
        imagePath: asNullableString(json['image_path']),
        sortOrder: asInt(json['sort_order']),
        isActive: asBool(json['is_active'], true),
      );
}

// ---------------------------------------------------------------------------
// Geography and addresses
// ---------------------------------------------------------------------------
class Town {
  const Town({required this.id, required this.name, required this.district, required this.state, this.pincodes = const []});
  final String id;
  final String name;
  final String district;
  final String state;
  final List<String> pincodes;

  factory Town.fromJson(Map<String, dynamic> json) => Town(
        id: asString(json['id']),
        name: asString(json['name']),
        district: asString(json['district']),
        state: asString(json['state']),
        pincodes: jsonStringList(json['pincodes']),
      );
}

class PincodeInfo {
  const PincodeInfo({required this.id, required this.pincode, required this.isActive});
  final String id;
  final String pincode;
  final bool isActive;

  factory PincodeInfo.fromJson(Map<String, dynamic> json) => PincodeInfo(
        id: asString(json['id']),
        pincode: asString(json['pincode']),
        isActive: asBool(json['is_active'], true),
      );
}

class AdminTown {
  const AdminTown({
    required this.id,
    required this.name,
    required this.district,
    required this.state,
    required this.isActive,
    required this.pincodes,
    this.latitude,
    this.longitude,
    this.ownStaffCovered = 0,
    this.partnersCovered = 0,
  });

  final String id;
  final String name;
  final String district;
  final String state;
  final bool isActive;
  final List<PincodeInfo> pincodes;
  final double? latitude;
  final double? longitude;
  final int ownStaffCovered;
  final int partnersCovered;

  factory AdminTown.fromJson(Map<String, dynamic> json) => AdminTown(
        id: asString(json['id']),
        name: asString(json['name']),
        district: asString(json['district']),
        state: asString(json['state']),
        isActive: asBool(json['is_active'], true),
        pincodes: mapJsonList(json['pincodes'], PincodeInfo.fromJson),
        latitude: json['latitude'] == null ? null : asDouble(json['latitude']),
        longitude: json['longitude'] == null ? null : asDouble(json['longitude']),
        ownStaffCovered: asInt(json['own_staff_covered']),
        partnersCovered: asInt(json['partners_covered']),
      );
}

class Address {
  const Address({
    required this.id,
    required this.label,
    required this.recipientName,
    required this.phone,
    required this.line1,
    required this.pincode,
    this.line2 = '',
    this.landmark = '',
    this.townId = '',
    this.townName = '',
    this.district = '',
    this.state = '',
    this.isDefault = false,
  });

  final String id;
  final String label;
  final String recipientName;
  final String phone;
  final String line1;
  final String line2;
  final String landmark;
  final String townId;
  final String townName;
  final String district;
  final String state;
  final String pincode;
  final bool isDefault;

  String get singleLine => [line1, if (line2.isNotEmpty) line2, if (landmark.isNotEmpty) landmark, townName, state, pincode]
      .where((part) => part.trim().isNotEmpty)
      .join(', ');

  factory Address.fromJson(Map<String, dynamic> json) => Address(
        id: asString(json['id']),
        label: asString(json['label'], 'Home'),
        recipientName: asString(json['recipient_name']),
        phone: asString(json['phone']),
        line1: asString(json['line1']),
        line2: asString(json['line2']),
        landmark: asString(json['landmark']),
        townId: asString(json['town_id']),
        townName: asString(json['town_name']),
        district: asString(json['district']),
        state: asString(json['state']),
        pincode: asString(json['pincode']),
        isDefault: asBool(json['is_default']),
      );
}

class Serviceability {
  const Serviceability({required this.serviceable, required this.message, this.townId, this.townName, this.towns = const []});
  final bool serviceable;
  final String message;
  final String? townId;
  final String? townName;
  final List<Town> towns;

  factory Serviceability.fromJson(Map<String, dynamic> json) => Serviceability(
        serviceable: asBool(json['serviceable']),
        message: asString(json['message'], 'Check delivery availability.'),
        townId: asNullableString(json['town_id']),
        townName: asNullableString(json['town_name']),
        towns: mapJsonList(json['towns'], Town.fromJson),
      );
}

// ---------------------------------------------------------------------------
// Cart, quote and orders
// ---------------------------------------------------------------------------
class CartItem {
  const CartItem({
    required this.productId,
    required this.name,
    required this.sku,
    required this.quantity,
    required this.unitPricePaise,
    required this.lineSubtotalPaise,
    required this.taxRateBps,
    required this.availableQuantity,
    required this.isAvailable,
    this.slug = '',
    this.primaryImagePath,
  });

  final String productId;
  final String name;
  final String slug;
  final String sku;
  final int quantity;
  final int unitPricePaise;
  final int lineSubtotalPaise;
  final int taxRateBps;
  final int availableQuantity;
  final bool isAvailable;
  final String? primaryImagePath;

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        productId: asString(json['product_id']),
        name: asString(json['name']),
        slug: asString(json['slug']),
        sku: asString(json['sku']),
        quantity: asInt(json['quantity']),
        unitPricePaise: asInt(json['unit_price_paise']),
        lineSubtotalPaise: asInt(json['line_subtotal_paise']),
        taxRateBps: asInt(json['tax_rate_bps']),
        availableQuantity: asInt(json['available_quantity']),
        isAvailable: asBool(json['is_available'], true),
        primaryImagePath: asNullableString(json['primary_image_path']),
      );
}

class Cart {
  const Cart({this.items = const [], this.subtotalPaise = 0, this.itemCount = 0});
  final List<CartItem> items;
  final int subtotalPaise;
  final int itemCount;
  bool get isEmpty => items.isEmpty;

  factory Cart.fromJson(Map<String, dynamic> json) => Cart(
        items: mapJsonList(json['items'], CartItem.fromJson),
        subtotalPaise: asInt(json['subtotal_paise']),
        itemCount: asInt(json['item_count']),
      );
}

class QuoteLine {
  const QuoteLine({
    required this.productId,
    required this.name,
    required this.sku,
    required this.quantity,
    required this.unitPricePaise,
    required this.taxPaise,
    required this.lineTotalPaise,
    required this.availableQuantity,
    required this.isAvailable,
    this.taxRateBps = 0,
    this.discountPaise = 0,
    this.hsnCode,
    this.isActive = true,
  });

  final String productId;
  final String name;
  final String sku;
  final String? hsnCode;
  final int quantity;
  final int unitPricePaise;
  final int discountPaise;
  final int taxRateBps;
  final int taxPaise;
  final int lineTotalPaise;
  final int availableQuantity;
  final bool isActive;
  final bool isAvailable;

  factory QuoteLine.fromJson(Map<String, dynamic> json) => QuoteLine(
        productId: asString(json['product_id']),
        name: asString(json['name']),
        sku: asString(json['sku']),
        hsnCode: asNullableString(json['hsn_code']),
        quantity: asInt(json['quantity']),
        unitPricePaise: asInt(json['unit_price_paise']),
        discountPaise: asInt(json['discount_paise']),
        taxRateBps: asInt(json['tax_rate_bps']),
        taxPaise: asInt(json['tax_paise']),
        lineTotalPaise: asInt(json['line_total_paise']),
        availableQuantity: asInt(json['available_quantity']),
        isActive: asBool(json['is_active'], true),
        isAvailable: asBool(json['is_available'], true),
      );
}

class Quote {
  const Quote({
    this.items = const [],
    this.itemCount = 0,
    this.subtotalPaise = 0,
    this.discountPaise = 0,
    this.taxPaise = 0,
    this.shippingPaise = 0,
    this.totalPaise = 0,
    this.codAmountPaise = 0,
    this.address,
  });

  final List<QuoteLine> items;
  final int itemCount;
  final int subtotalPaise;
  final int discountPaise;
  final int taxPaise;
  final int shippingPaise;
  final int totalPaise;
  final int codAmountPaise;
  final Address? address;

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
        items: mapJsonList(json['items'], QuoteLine.fromJson),
        itemCount: asInt(json['item_count']),
        subtotalPaise: asInt(json['subtotal_paise']),
        discountPaise: asInt(json['discount_paise']),
        taxPaise: asInt(json['tax_paise']),
        shippingPaise: asInt(json['shipping_paise']),
        totalPaise: asInt(json['total_paise']),
        codAmountPaise: asInt(json['cod_amount_paise']),
        address: json['address'] == null ? null : Address.fromJson(jsonMap(json['address'])),
      );
}

class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.paymentStatus,
    required this.totalPaise,
    required this.codAmountPaise,
    required this.itemCount,
    required this.createdAt,
    this.townName = '',
    this.pincode = '',
    this.deliveredAt,
    this.shipmentId,
    this.shipmentStatus,
    this.invoiceNumber,
    this.firstItemName,
    this.returnStatus,
  });

  final String id;
  final String orderNumber;
  final String status;
  final String paymentStatus;
  final int totalPaise;
  final int codAmountPaise;
  final int itemCount;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final String townName;
  final String pincode;
  final String? shipmentId;
  final String? shipmentStatus;
  final String? invoiceNumber;
  final String? firstItemName;
  final String? returnStatus;

  factory OrderSummary.fromJson(Map<String, dynamic> json) => OrderSummary(
        id: asString(json['id']),
        orderNumber: asString(json['order_number']),
        status: asString(json['status'], 'PENDING_APPROVAL'),
        paymentStatus: asString(json['payment_status'], 'PENDING'),
        totalPaise: asInt(json['total_paise']),
        codAmountPaise: asInt(json['cod_amount_paise']),
        itemCount: asInt(json['item_count']),
        createdAt: asRequiredDate(json['created_at']),
        deliveredAt: asDate(json['delivered_at']),
        townName: asString(json['town_name']),
        pincode: asString(json['pincode']),
        shipmentId: asNullableString(json['shipment_id']),
        shipmentStatus: asNullableString(json['shipment_status']),
        invoiceNumber: asNullableString(json['invoice_number']),
        firstItemName: asNullableString(json['first_item_name']),
        returnStatus: asNullableString(json['return_status']),
      );
}

class OrderItem {
  const OrderItem({
    required this.productName,
    required this.sku,
    required this.quantity,
    required this.unitPricePaise,
    required this.taxPaise,
    required this.lineTotalPaise,
    this.productId,
    this.hsnCode,
    this.discountPaise = 0,
    this.taxRateBps = 0,
  });

  final String? productId;
  final String productName;
  final String sku;
  final String? hsnCode;
  final int quantity;
  final int unitPricePaise;
  final int discountPaise;
  final int taxRateBps;
  final int taxPaise;
  final int lineTotalPaise;

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        productId: asNullableString(json['product_id']),
        productName: asString(json['product_name']),
        sku: asString(json['sku']),
        hsnCode: asNullableString(json['hsn_code']),
        quantity: asInt(json['quantity']),
        unitPricePaise: asInt(json['unit_price_paise']),
        discountPaise: asInt(json['discount_paise']),
        taxRateBps: asInt(json['tax_rate_bps']),
        taxPaise: asInt(json['tax_paise']),
        lineTotalPaise: asInt(json['line_total_paise']),
      );
}

class InvoiceInfo {
  const InvoiceInfo({
    required this.id,
    required this.invoiceNumber,
    required this.status,
    required this.totalPaise,
    this.invoiceDate,
    this.pdfStoragePath,
  });
  final String id;
  final String invoiceNumber;
  final String status;
  final int totalPaise;
  final DateTime? invoiceDate;
  final String? pdfStoragePath;

  factory InvoiceInfo.fromJson(Map<String, dynamic> json) => InvoiceInfo(
        id: asString(json['id']),
        invoiceNumber: asString(json['invoice_number']),
        status: asString(json['status']),
        totalPaise: asInt(json['total_paise']),
        invoiceDate: asDate(json['invoice_date']),
        pdfStoragePath: asNullableString(json['pdf_storage_path']),
      );
}

class ShipmentInfo {
  const ShipmentInfo({
    required this.id,
    required this.shipmentNumber,
    required this.status,
    required this.packageCount,
    required this.expectedCodPaise,
    this.pickedUpAt,
    this.deliveredAt,
  });
  final String id;
  final String shipmentNumber;
  final String status;
  final int packageCount;
  final int expectedCodPaise;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;

  factory ShipmentInfo.fromJson(Map<String, dynamic> json) => ShipmentInfo(
        id: asString(json['id']),
        shipmentNumber: asString(json['shipment_number']),
        status: asString(json['status']),
        packageCount: asInt(json['package_count']),
        expectedCodPaise: asInt(json['expected_cod_paise']),
        pickedUpAt: asDate(json['picked_up_at']),
        deliveredAt: asDate(json['delivered_at']),
      );
}

class ReturnSummary {
  const ReturnSummary({
    required this.id,
    required this.returnNumber,
    required this.status,
    required this.reason,
    required this.createdAt,
    this.rejectionReason,
    this.resolutionNote,
  });
  final String id;
  final String returnNumber;
  final String status;
  final String reason;
  final DateTime createdAt;
  final String? rejectionReason;
  final String? resolutionNote;

  factory ReturnSummary.fromJson(Map<String, dynamic> json) => ReturnSummary(
        id: asString(json['id']),
        returnNumber: asString(json['return_number']),
        status: asString(json['status']),
        reason: asString(json['reason']),
        createdAt: asRequiredDate(json['created_at']),
        rejectionReason: asNullableString(json['rejection_reason']),
        resolutionNote: asNullableString(json['resolution_note']),
      );
}

class OrderDetail {
  const OrderDetail({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.paymentStatus,
    required this.subtotalPaise,
    required this.discountPaise,
    required this.taxPaise,
    required this.shippingPaise,
    required this.totalPaise,
    required this.codAmountPaise,
    required this.itemCount,
    required this.recipientName,
    required this.phone,
    required this.line1,
    required this.townName,
    required this.district,
    required this.state,
    required this.pincode,
    required this.createdAt,
    this.paymentMethod = 'COD',
    this.line2 = '',
    this.landmark = '',
    this.customerNote = '',
    this.approvedAt,
    this.deliveredAt,
    this.cancelledAt,
    this.rejectedReason,
    this.items = const [],
    this.invoice,
    this.shipment,
    this.returnRequest,
  });

  final String id;
  final String orderNumber;
  final String status;
  final String paymentMethod;
  final String paymentStatus;
  final int subtotalPaise;
  final int discountPaise;
  final int taxPaise;
  final int shippingPaise;
  final int totalPaise;
  final int codAmountPaise;
  final int itemCount;
  final String recipientName;
  final String phone;
  final String line1;
  final String line2;
  final String landmark;
  final String townName;
  final String district;
  final String state;
  final String pincode;
  final String customerNote;
  final DateTime createdAt;
  final DateTime? approvedAt;
  final DateTime? deliveredAt;
  final DateTime? cancelledAt;
  final String? rejectedReason;
  final List<OrderItem> items;
  final InvoiceInfo? invoice;
  final ShipmentInfo? shipment;
  final ReturnSummary? returnRequest;

  String get addressLine => [line1, if (line2.isNotEmpty) line2, if (landmark.isNotEmpty) landmark, townName, district, state, pincode]
      .where((part) => part.trim().isNotEmpty)
      .join(', ');

  factory OrderDetail.fromJson(Map<String, dynamic> json) => OrderDetail(
        id: asString(json['id']),
        orderNumber: asString(json['order_number']),
        status: asString(json['status']),
        paymentMethod: asString(json['payment_method'], 'COD'),
        paymentStatus: asString(json['payment_status'], 'PENDING'),
        subtotalPaise: asInt(json['subtotal_paise']),
        discountPaise: asInt(json['discount_paise']),
        taxPaise: asInt(json['tax_paise']),
        shippingPaise: asInt(json['shipping_paise']),
        totalPaise: asInt(json['total_paise']),
        codAmountPaise: asInt(json['cod_amount_paise']),
        itemCount: asInt(json['item_count']),
        recipientName: asString(json['recipient_name']),
        phone: asString(json['phone']),
        line1: asString(json['line1']),
        line2: asString(json['line2']),
        landmark: asString(json['landmark']),
        townName: asString(json['town_name']),
        district: asString(json['district']),
        state: asString(json['state']),
        pincode: asString(json['pincode']),
        customerNote: asString(json['customer_note']),
        createdAt: asRequiredDate(json['created_at']),
        approvedAt: asDate(json['approved_at']),
        deliveredAt: asDate(json['delivered_at']),
        cancelledAt: asDate(json['cancelled_at']),
        rejectedReason: asNullableString(json['rejected_reason']),
        items: mapJsonList(json['items'], OrderItem.fromJson),
        invoice: json['invoice'] == null ? null : InvoiceInfo.fromJson(jsonMap(json['invoice'])),
        shipment: json['shipment'] == null ? null : ShipmentInfo.fromJson(jsonMap(json['shipment'])),
        returnRequest: json['return_request'] == null ? null : ReturnSummary.fromJson(jsonMap(json['return_request'])),
      );
}

class TrackingEvent {
  const TrackingEvent({
    required this.eventType,
    required this.newStatus,
    required this.createdAt,
    this.previousStatus,
    this.source = '',
    this.notes,
    this.locationText,
  });
  final String eventType;
  final String? previousStatus;
  final String newStatus;
  final String source;
  final String? notes;
  final String? locationText;
  final DateTime createdAt;

  factory TrackingEvent.fromJson(Map<String, dynamic> json) => TrackingEvent(
        eventType: asString(json['event_type']),
        previousStatus: asNullableString(json['previous_status']),
        newStatus: asString(json['new_status']),
        source: asString(json['source']),
        notes: asNullableString(json['notes']),
        locationText: asNullableString(json['location_text']),
        createdAt: asRequiredDate(json['created_at']),
      );
}

class TrackingPackage {
  const TrackingPackage({required this.packageNumber, required this.status, this.isSealed = false});
  final String packageNumber;
  final String status;
  final bool isSealed;

  factory TrackingPackage.fromJson(Map<String, dynamic> json) => TrackingPackage(
        packageNumber: asString(json['package_number']),
        status: asString(json['status']),
        isSealed: asBool(json['is_sealed']),
      );
}

class Tracking {
  const Tracking({
    required this.orderId,
    required this.orderNumber,
    required this.orderStatus,
    this.paymentStatus = '',
    this.shipmentId,
    this.shipmentNumber,
    this.shipmentStatus,
    this.packageCount = 0,
    this.events = const [],
    this.packages = const [],
    this.deliveryOtp,
    this.deliveryOtpNotice,
  });

  final String orderId;
  final String orderNumber;
  final String orderStatus;
  final String paymentStatus;
  final String? shipmentId;
  final String? shipmentNumber;
  final String? shipmentStatus;
  final int packageCount;
  final List<TrackingEvent> events;
  final List<TrackingPackage> packages;
  final String? deliveryOtp;
  final String? deliveryOtpNotice;

  factory Tracking.fromJson(Map<String, dynamic> json) => Tracking(
        orderId: asString(json['order_id']),
        orderNumber: asString(json['order_number']),
        orderStatus: asString(json['order_status']),
        paymentStatus: asString(json['payment_status']),
        shipmentId: asNullableString(json['shipment_id']),
        shipmentNumber: asNullableString(json['shipment_number']),
        shipmentStatus: asNullableString(json['shipment_status']),
        packageCount: asInt(json['package_count']),
        events: mapJsonList(json['events'], TrackingEvent.fromJson),
        packages: mapJsonList(json['packages'], TrackingPackage.fromJson),
        deliveryOtp: asNullableString(json['delivery_otp']),
        deliveryOtpNotice: asNullableString(json['delivery_otp_notice']),
      );
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.data = const {},
    this.readAt,
  });
  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime? readAt;
  final DateTime createdAt;
  bool get unread => readAt == null;

  factory NotificationItem.fromJson(Map<String, dynamic> json) => NotificationItem(
        id: asString(json['id']),
        type: asString(json['type']),
        title: asString(json['title']),
        body: asString(json['body']),
        data: jsonMap(json['data']),
        readAt: asDate(json['read_at']),
        createdAt: asRequiredDate(json['created_at']),
      );
}

// ---------------------------------------------------------------------------
// Owner read models
// ---------------------------------------------------------------------------
class RecentOrder {
  const RecentOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.totalPaise,
    required this.itemCount,
    required this.createdAt,
    this.customerName = '',
    this.customerPhone,
    this.townName = '',
  });

  final String id;
  final String orderNumber;
  final String status;
  final int totalPaise;
  final int itemCount;
  final DateTime createdAt;
  final String customerName;
  final String? customerPhone;
  final String townName;

  factory RecentOrder.fromJson(Map<String, dynamic> json) => RecentOrder(
        id: asString(json['id']),
        orderNumber: asString(json['order_number']),
        status: asString(json['status']),
        totalPaise: asInt(json['total_paise']),
        itemCount: asInt(json['item_count']),
        createdAt: asRequiredDate(json['created_at']),
        customerName: asString(json['customer_name']),
        customerPhone: asNullableString(json['customer_phone']),
        townName: asString(json['town_name']),
      );
}

class RecentActivity {
  const RecentActivity({required this.eventType, required this.createdAt, this.orderNumber = '', this.shipmentNumber = ''});
  final String eventType;
  final DateTime createdAt;
  final String orderNumber;
  final String shipmentNumber;

  factory RecentActivity.fromJson(Map<String, dynamic> json) => RecentActivity(
        eventType: asString(json['event_type']),
        createdAt: asRequiredDate(json['created_at']),
        orderNumber: asString(json['order_number']),
        shipmentNumber: asString(json['shipment_number']),
      );
}

class OwnerDashboard {
  const OwnerDashboard({
    required this.ordersToday,
    required this.pendingApproval,
    required this.readyForPickup,
    required this.pickupsInProgress,
    required this.packagesWaitingPickup,
    required this.outForDelivery,
    required this.deliveredToday,
    required this.deliveredValueTodayPaise,
    required this.codPendingVerificationPaise,
    required this.lowStockProducts,
    required this.activeProducts,
    required this.pendingReturns,
    required this.unreadNotifications,
    this.recentOrders = const [],
    this.recentActivity = const [],
    this.timezone = 'Asia/Kolkata',
  });

  final int ordersToday;
  final int pendingApproval;
  final int readyForPickup;
  final int pickupsInProgress;
  final int packagesWaitingPickup;
  final int outForDelivery;
  final int deliveredToday;
  final int deliveredValueTodayPaise;
  final int codPendingVerificationPaise;
  final int lowStockProducts;
  final int activeProducts;
  final int pendingReturns;
  final int unreadNotifications;
  final List<RecentOrder> recentOrders;
  final List<RecentActivity> recentActivity;
  final String timezone;

  factory OwnerDashboard.fromJson(Map<String, dynamic> json) => OwnerDashboard(
        ordersToday: asInt(json['orders_today']),
        pendingApproval: asInt(json['pending_approval']),
        readyForPickup: asInt(json['ready_for_pickup']),
        pickupsInProgress: asInt(json['pickups_in_progress']),
        packagesWaitingPickup: asInt(json['packages_waiting_pickup']),
        outForDelivery: asInt(json['out_for_delivery']),
        deliveredToday: asInt(json['delivered_today']),
        deliveredValueTodayPaise: asInt(json['delivered_value_today_paise']),
        codPendingVerificationPaise: asInt(json['cod_pending_verification_paise']),
        lowStockProducts: asInt(json['low_stock_products']),
        activeProducts: asInt(json['active_products']),
        pendingReturns: asInt(json['pending_returns']),
        unreadNotifications: asInt(json['unread_notifications']),
        recentOrders: mapJsonList(json['recent_orders'], RecentOrder.fromJson),
        recentActivity: mapJsonList(json['recent_activity'], RecentActivity.fromJson),
        timezone: asString(json['timezone'], 'Asia/Kolkata'),
      );
}

class AdminOrderSummary {
  const AdminOrderSummary({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.paymentStatus,
    required this.totalPaise,
    required this.codAmountPaise,
    required this.itemCount,
    required this.createdAt,
    this.customerName = '',
    this.customerPhone,
    this.townName = '',
    this.pincode = '',
    this.shipmentStatus,
    this.paymentCollectedAt,
  });

  final String id;
  final String orderNumber;
  final String status;
  final String paymentStatus;
  final int totalPaise;
  final int codAmountPaise;
  final int itemCount;
  final DateTime createdAt;
  final String customerName;
  final String? customerPhone;
  final String townName;
  final String pincode;
  final String? shipmentStatus;
  final DateTime? paymentCollectedAt;

  factory AdminOrderSummary.fromJson(Map<String, dynamic> json) => AdminOrderSummary(
        id: asString(json['id']),
        orderNumber: asString(json['order_number']),
        status: asString(json['status']),
        paymentStatus: asString(json['payment_status']),
        totalPaise: asInt(json['total_paise']),
        codAmountPaise: asInt(json['cod_amount_paise']),
        itemCount: asInt(json['item_count']),
        createdAt: asRequiredDate(json['created_at']),
        customerName: asString(json['customer_name']),
        customerPhone: asNullableString(json['customer_phone']),
        townName: asString(json['town_name']),
        pincode: asString(json['pincode']),
        shipmentStatus: asNullableString(json['shipment_status']),
        paymentCollectedAt: asDate(json['payment_collected_at']),
      );
}

class OrderCustomer {
  const OrderCustomer({this.id = '', this.name = '', this.phone, this.email});
  final String id;
  final String name;
  final String? phone;
  final String? email;
  factory OrderCustomer.fromJson(Map<String, dynamic> json) => OrderCustomer(
        id: asString(json['id']),
        name: asString(json['name']),
        phone: asNullableString(json['phone']),
        email: asNullableString(json['email']),
      );
}

class PickupAssignmentBrief {
  const PickupAssignmentBrief({
    required this.id,
    required this.status,
    this.staffUserId,
    this.staffName,
    this.staffPhone,
    this.staffType,
    this.mode,
    this.partnerName,
    this.assignedAt,
    this.expiresAt,
  });
  final String id;
  final String status;
  final String? staffUserId;
  final String? staffName;
  final String? staffPhone;
  final String? staffType;
  final String? mode;
  final String? partnerName;
  final DateTime? assignedAt;
  final DateTime? expiresAt;

  factory PickupAssignmentBrief.fromJson(Map<String, dynamic> json) => PickupAssignmentBrief(
        id: asString(json['id']),
        status: asString(json['status']),
        staffUserId: asNullableString(json['staff_user_id']),
        staffName: asNullableString(json['staff_name']),
        staffPhone: asNullableString(json['staff_phone']),
        staffType: asNullableString(json['staff_type']),
        mode: asNullableString(json['mode']),
        partnerName: asNullableString(json['partner_name']),
        assignedAt: asDate(json['assigned_at']),
        expiresAt: asDate(json['expires_at']),
      );
}

class PickupInfo {
  const PickupInfo({
    required this.id,
    required this.pickupNumber,
    required this.status,
    this.condition,
    this.packageCountExpected = 0,
    this.packageCountVerified = 0,
    this.requestedAt,
    this.verifiedAt,
    this.otp,
    this.otpExpiresAt,
    this.scannedPackages = 0,
    this.assignment,
  });
  final String id;
  final String pickupNumber;
  final String status;
  final String? condition;
  final int packageCountExpected;
  final int packageCountVerified;
  final DateTime? requestedAt;
  final DateTime? verifiedAt;
  final String? otp;
  final DateTime? otpExpiresAt;
  final int scannedPackages;
  final PickupAssignmentBrief? assignment;

  factory PickupInfo.fromJson(Map<String, dynamic> json) => PickupInfo(
        id: asString(json['id']),
        pickupNumber: asString(json['pickup_number']),
        status: asString(json['status']),
        condition: asNullableString(json['condition']),
        packageCountExpected: asInt(json['package_count_expected']),
        packageCountVerified: asInt(json['package_count_verified']),
        requestedAt: asDate(json['requested_at']),
        verifiedAt: asDate(json['verified_at']),
        otp: asNullableString(json['otp']),
        otpExpiresAt: asDate(json['otp_expires_at']),
        scannedPackages: asInt(json['scanned_packages']),
        assignment: json['assignment'] == null ? null : PickupAssignmentBrief.fromJson(jsonMap(json['assignment'])),
      );
}

class PackageInfo {
  const PackageInfo({
    required this.id,
    required this.packageNumber,
    required this.status,
    required this.isSealed,
    this.packageCode = '',
    this.weightGrams = 0,
    this.scanned = false,
  });
  final String id;
  final String packageNumber;
  final String packageCode;
  final String status;
  final bool isSealed;
  final int weightGrams;
  final bool scanned;

  factory PackageInfo.fromJson(Map<String, dynamic> json) => PackageInfo(
        id: asString(json['id']),
        packageNumber: asString(json['package_number']),
        packageCode: asString(json['package_code']),
        status: asString(json['status']),
        isSealed: asBool(json['is_sealed']),
        weightGrams: asInt(json['weight_grams']),
        scanned: asBool(json['scanned']),
      );
}

class AdminOrderDetail {
  const AdminOrderDetail({
    required this.order,
    required this.customer,
    this.pickup,
    this.deliveryAssignmentId,
    this.deliveryStaffUserId,
    this.deliveryStatus,
    this.packages = const [],
  });
  final OrderDetail order;
  final OrderCustomer customer;
  final PickupInfo? pickup;
  final String? deliveryAssignmentId;
  final String? deliveryStaffUserId;
  final String? deliveryStatus;
  final List<PackageInfo> packages;

  factory AdminOrderDetail.fromJson(Map<String, dynamic> json) {
    final delivery = jsonMap(json['delivery_assignment']);
    return AdminOrderDetail(
      order: OrderDetail.fromJson(json),
      customer: json['customer'] == null ? const OrderCustomer() : OrderCustomer.fromJson(jsonMap(json['customer'])),
      pickup: json['pickup'] == null ? null : PickupInfo.fromJson(jsonMap(json['pickup'])),
      deliveryAssignmentId: asNullableString(delivery['id']),
      deliveryStaffUserId: asNullableString(delivery['staff_user_id']),
      deliveryStatus: asNullableString(delivery['status']),
      packages: mapJsonList(json['packages_detail'], PackageInfo.fromJson),
    );
  }
}

class PickupListItem {
  const PickupListItem({
    required this.id,
    required this.pickupNumber,
    required this.status,
    required this.orderId,
    required this.orderNumber,
    required this.orderStatus,
    this.condition,
    this.packageCountExpected = 0,
    this.packageCountVerified = 0,
    this.scannedPackages = 0,
    this.requestedAt,
    this.verifiedAt,
    this.customerName = '',
    this.customerPhone,
    this.townName = '',
    this.pincode = '',
    this.totalPaise = 0,
    this.shipmentId,
    this.shipmentNumber,
    this.shipmentStatus,
    this.otp,
    this.otpExpiresAt,
    this.assignment,
  });

  final String id;
  final String pickupNumber;
  final String status;
  final String? condition;
  final int packageCountExpected;
  final int packageCountVerified;
  final int scannedPackages;
  final DateTime? requestedAt;
  final DateTime? verifiedAt;
  final String orderId;
  final String orderNumber;
  final String orderStatus;
  final String customerName;
  final String? customerPhone;
  final String townName;
  final String pincode;
  final int totalPaise;
  final String? shipmentId;
  final String? shipmentNumber;
  final String? shipmentStatus;
  final String? otp;
  final DateTime? otpExpiresAt;
  final PickupAssignmentBrief? assignment;

  factory PickupListItem.fromJson(Map<String, dynamic> json) => PickupListItem(
        id: asString(json['id']),
        pickupNumber: asString(json['pickup_number']),
        status: asString(json['status']),
        condition: asNullableString(json['condition']),
        packageCountExpected: asInt(json['package_count_expected']),
        packageCountVerified: asInt(json['package_count_verified']),
        scannedPackages: asInt(json['scanned_packages']),
        requestedAt: asDate(json['requested_at']),
        verifiedAt: asDate(json['verified_at']),
        orderId: asString(json['order_id']),
        orderNumber: asString(json['order_number']),
        orderStatus: asString(json['order_status']),
        customerName: asString(json['customer_name']),
        customerPhone: asNullableString(json['customer_phone']),
        townName: asString(json['town_name']),
        pincode: asString(json['pincode']),
        totalPaise: asInt(json['total_paise']),
        shipmentId: asNullableString(json['shipment_id']),
        shipmentNumber: asNullableString(json['shipment_number']),
        shipmentStatus: asNullableString(json['shipment_status']),
        otp: asNullableString(json['otp']),
        otpExpiresAt: asDate(json['otp_expires_at']),
        assignment: json['assignment'] == null ? null : PickupAssignmentBrief.fromJson(jsonMap(json['assignment'])),
      );
}

class DeliveryAssignmentBrief {
  const DeliveryAssignmentBrief({
    required this.id,
    required this.status,
    this.staffUserId,
    this.staffName,
    this.staffPhone,
    this.staffType,
    this.partnerName,
    this.assignedAt,
  });
  final String id;
  final String status;
  final String? staffUserId;
  final String? staffName;
  final String? staffPhone;
  final String? staffType;
  final String? partnerName;
  final DateTime? assignedAt;

  factory DeliveryAssignmentBrief.fromJson(Map<String, dynamic> json) => DeliveryAssignmentBrief(
        id: asString(json['id']),
        status: asString(json['status']),
        staffUserId: asNullableString(json['staff_user_id']),
        staffName: asNullableString(json['staff_name']),
        staffPhone: asNullableString(json['staff_phone']),
        staffType: asNullableString(json['staff_type']),
        partnerName: asNullableString(json['partner_name']),
        assignedAt: asDate(json['assigned_at']),
      );
}

class DeliveryListItem {
  const DeliveryListItem({
    required this.shipmentId,
    required this.shipmentNumber,
    required this.status,
    required this.orderId,
    required this.orderNumber,
    this.packageCount = 0,
    this.expectedCodPaise = 0,
    this.createdAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.customerName = '',
    this.customerPhone,
    this.townName = '',
    this.pincode = '',
    this.assignment,
    this.lastEventType,
    this.lastEventAt,
    this.attempts = 0,
  });

  final String shipmentId;
  final String shipmentNumber;
  final String status;
  final int packageCount;
  final int expectedCodPaise;
  final DateTime? createdAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final String orderId;
  final String orderNumber;
  final String customerName;
  final String? customerPhone;
  final String townName;
  final String pincode;
  final DeliveryAssignmentBrief? assignment;
  final String? lastEventType;
  final DateTime? lastEventAt;
  final int attempts;

  factory DeliveryListItem.fromJson(Map<String, dynamic> json) {
    final lastEvent = jsonMap(json['last_event']);
    return DeliveryListItem(
      shipmentId: asString(json['shipment_id']),
      shipmentNumber: asString(json['shipment_number']),
      status: asString(json['status']),
      packageCount: asInt(json['package_count']),
      expectedCodPaise: asInt(json['expected_cod_paise']),
      createdAt: asDate(json['created_at']),
      pickedUpAt: asDate(json['picked_up_at']),
      deliveredAt: asDate(json['delivered_at']),
      orderId: asString(json['order_id']),
      orderNumber: asString(json['order_number']),
      customerName: asString(json['customer_name']),
      customerPhone: asNullableString(json['customer_phone']),
      townName: asString(json['town_name']),
      pincode: asString(json['pincode']),
      assignment: json['assignment'] == null ? null : DeliveryAssignmentBrief.fromJson(jsonMap(json['assignment'])),
      lastEventType: asNullableString(lastEvent['event_type']),
      lastEventAt: asDate(lastEvent['created_at']),
      attempts: asInt(json['attempts']),
    );
  }
}

class Personnel {
  const Personnel({
    required this.staffUserId,
    required this.staffType,
    required this.displayName,
    required this.status,
    required this.isAvailable,
    this.partnerId,
    this.partnerName,
    this.phone,
    this.employeeCode,
    this.capacityPerDay = 0,
    this.activeTasks = 0,
    this.coverageLabel = '',
  });

  final String staffUserId;
  final String staffType;
  final String displayName;
  final String status;
  final bool isAvailable;
  final String? partnerId;
  final String? partnerName;
  final String? phone;
  final String? employeeCode;
  final int capacityPerDay;
  final int activeTasks;
  final String coverageLabel;

  factory Personnel.fromJson(Map<String, dynamic> json) => Personnel(
        staffUserId: asString(json['staff_user_id']),
        staffType: asString(json['staff_type']),
        displayName: asString(json['display_name']),
        status: asString(json['status']),
        isAvailable: asBool(json['is_available']),
        partnerId: asNullableString(json['partner_id']),
        partnerName: asNullableString(json['partner_name']),
        phone: asNullableString(json['phone']),
        employeeCode: asNullableString(json['employee_code']),
        capacityPerDay: asInt(json['capacity_per_day']),
        activeTasks: asInt(json['active_tasks']),
        coverageLabel: asString(json['coverage_label']),
      );
}

class StaffInvite {
  const StaffInvite({
    required this.id,
    required this.phone,
    required this.role,
    required this.displayName,
    required this.expiresAt,
    this.partnerId,
    this.partnerName,
    this.usedAt,
    this.revokedAt,
    this.canManagePartnerStaff = false,
    this.createdAt,
    this.activationCode,
  });
  final String id;
  final String phone;
  final String role;
  final String displayName;
  final DateTime expiresAt;
  final String? partnerId;
  final String? partnerName;
  final DateTime? usedAt;
  final DateTime? revokedAt;
  final bool canManagePartnerStaff;
  final DateTime? createdAt;
  final String? activationCode;

  bool get isActive => usedAt == null && revokedAt == null && expiresAt.isAfter(DateTime.now());

  factory StaffInvite.fromJson(Map<String, dynamic> json) => StaffInvite(
        id: asString(json['id'] ?? json['invite_id']),
        phone: asString(json['phone']),
        role: asString(json['role']),
        displayName: asString(json['display_name']),
        expiresAt: asRequiredDate(json['expires_at']),
        partnerId: asNullableString(json['partner_id']),
        partnerName: asNullableString(json['partner_name']),
        usedAt: asDate(json['used_at']),
        revokedAt: asDate(json['revoked_at']),
        canManagePartnerStaff: asBool(json['can_manage_partner_staff']),
        createdAt: asDate(json['created_at']),
        activationCode: asNullableString(json['activation_code']),
      );
}

class PartnerCoverage {
  const PartnerCoverage({required this.townId, required this.townName, this.pincode});
  final String townId;
  final String townName;
  final String? pincode;
  factory PartnerCoverage.fromJson(Map<String, dynamic> json) => PartnerCoverage(
        townId: asString(json['town_id']),
        townName: asString(json['town_name']),
        pincode: asNullableString(json['pincode']),
      );
}

class Partner {
  const Partner({
    required this.id,
    required this.name,
    required this.code,
    required this.status,
    this.contactName = '',
    this.phone,
    this.email,
    this.codCreditLimitPaise = 0,
    this.settlementCycleDays = 1,
    this.notes = '',
    this.staffCount = 0,
    this.activeStaffCount = 0,
    this.coverage = const [],
  });
  final String id;
  final String name;
  final String code;
  final String status;
  final String contactName;
  final String? phone;
  final String? email;
  final int codCreditLimitPaise;
  final int settlementCycleDays;
  final String notes;
  final int staffCount;
  final int activeStaffCount;
  final List<PartnerCoverage> coverage;

  factory Partner.fromJson(Map<String, dynamic> json) => Partner(
        id: asString(json['id']),
        name: asString(json['name']),
        code: asString(json['code']),
        status: asString(json['status']),
        contactName: asString(json['contact_name']),
        phone: asNullableString(json['phone']),
        email: asNullableString(json['email']),
        codCreditLimitPaise: asInt(json['cod_credit_limit_paise']),
        settlementCycleDays: asInt(json['settlement_cycle_days'], 1),
        notes: asString(json['notes']),
        staffCount: asInt(json['staff_count']),
        activeStaffCount: asInt(json['active_staff_count']),
        coverage: mapJsonList(json['coverage'], PartnerCoverage.fromJson),
      );
}

class CodStaffBalance {
  const CodStaffBalance({
    required this.staffUserId,
    required this.staffName,
    required this.staffType,
    required this.collectedPaise,
    required this.handedOverPaise,
    required this.cashInCustodyPaise,
    this.staffPhone,
    this.partnerName,
    this.lastCollectionAt,
  });
  final String staffUserId;
  final String staffName;
  final String? staffPhone;
  final String staffType;
  final String? partnerName;
  final int collectedPaise;
  final int handedOverPaise;
  final int cashInCustodyPaise;
  final DateTime? lastCollectionAt;

  factory CodStaffBalance.fromJson(Map<String, dynamic> json) => CodStaffBalance(
        staffUserId: asString(json['staff_user_id']),
        staffName: asString(json['staff_name']),
        staffPhone: asNullableString(json['staff_phone']),
        staffType: asString(json['staff_type']),
        partnerName: asNullableString(json['partner_name']),
        collectedPaise: asInt(json['collected_paise']),
        handedOverPaise: asInt(json['declared_handover_paise']),
        cashInCustodyPaise: asInt(json['cash_in_custody_paise']),
        lastCollectionAt: asDate(json['last_collection_at']),
      );
}

class CodSettlementItem {
  const CodSettlementItem({
    required this.shipmentId,
    required this.shipmentNumber,
    required this.orderNumber,
    required this.expectedPaise,
    required this.collectedPaise,
  });
  final String shipmentId;
  final String shipmentNumber;
  final String orderNumber;
  final int expectedPaise;
  final int collectedPaise;

  factory CodSettlementItem.fromJson(Map<String, dynamic> json) => CodSettlementItem(
        shipmentId: asString(json['shipment_id']),
        shipmentNumber: asString(json['shipment_number']),
        orderNumber: asString(json['order_number']),
        expectedPaise: asInt(json['expected_paise']),
        collectedPaise: asInt(json['collected_paise']),
      );
}

class CodSettlement {
  const CodSettlement({
    required this.id,
    required this.settlementNumber,
    required this.staffUserId,
    required this.staffName,
    required this.staffType,
    required this.expectedPaise,
    required this.collectedPaise,
    required this.handedOverPaise,
    required this.countedPaise,
    required this.shortagePaise,
    required this.excessPaise,
    required this.status,
    required this.declaredAt,
    this.staffPhone,
    this.partnerName,
    this.verifiedAt,
    this.note,
    this.rejectionReason,
    this.items = const [],
    this.itemCount = 0,
  });

  final String id;
  final String settlementNumber;
  final String staffUserId;
  final String staffName;
  final String? staffPhone;
  final String staffType;
  final String? partnerName;
  final int expectedPaise;
  final int collectedPaise;
  final int handedOverPaise;
  final int countedPaise;
  final int shortagePaise;
  final int excessPaise;
  final String status;
  final DateTime declaredAt;
  final DateTime? verifiedAt;
  final String? note;
  final String? rejectionReason;
  final List<CodSettlementItem> items;
  final int itemCount;

  factory CodSettlement.fromJson(Map<String, dynamic> json) => CodSettlement(
        id: asString(json['id']),
        settlementNumber: asString(json['settlement_number']),
        staffUserId: asString(json['staff_user_id']),
        staffName: asString(json['staff_name']),
        staffPhone: asNullableString(json['staff_phone']),
        staffType: asString(json['staff_type']),
        partnerName: asNullableString(json['partner_name']),
        expectedPaise: asInt(json['expected_paise']),
        collectedPaise: asInt(json['collected_paise']),
        handedOverPaise: asInt(json['handed_over_paise']),
        countedPaise: asInt(json['counted_paise']),
        shortagePaise: asInt(json['shortage_paise']),
        excessPaise: asInt(json['excess_paise']),
        status: asString(json['status']),
        declaredAt: asRequiredDate(json['declared_at']),
        verifiedAt: asDate(json['verified_at']),
        note: asNullableString(json['note']),
        rejectionReason: asNullableString(json['rejection_reason']),
        items: mapJsonList(json['items'], CodSettlementItem.fromJson),
        itemCount: asInt(json['item_count']),
      );
}

class CodTransaction {
  const CodTransaction({
    required this.id,
    required this.entryType,
    required this.amountPaise,
    required this.createdAt,
    this.description,
    this.shipmentId,
    this.orderId,
    this.staffUserId,
  });
  final String id;
  final String entryType;
  final int amountPaise;
  final DateTime createdAt;
  final String? description;
  final String? shipmentId;
  final String? orderId;
  final String? staffUserId;

  factory CodTransaction.fromJson(Map<String, dynamic> json) => CodTransaction(
        id: asString(json['id']),
        entryType: asString(json['entry_type']),
        amountPaise: asInt(json['amount_paise']),
        createdAt: asRequiredDate(json['created_at']),
        description: asNullableString(json['description']),
        shipmentId: asNullableString(json['shipment_id']),
        orderId: asNullableString(json['order_id']),
        staffUserId: asNullableString(json['staff_user_id']),
      );
}

class CodOverview {
  const CodOverview({
    required this.expectedPaise,
    required this.collectedPaise,
    required this.handedOverPaise,
    required this.cashWithStaffPaise,
    required this.pendingVerificationPaise,
    required this.verifiedPaise,
    required this.shortagePaise,
    required this.excessPaise,
    required this.openSettlements,
    this.staffBalances = const [],
    this.settlements = const [],
    this.recentTransactions = const [],
  });

  final int expectedPaise;
  final int collectedPaise;
  final int handedOverPaise;
  final int cashWithStaffPaise;
  final int pendingVerificationPaise;
  final int verifiedPaise;
  final int shortagePaise;
  final int excessPaise;
  final int openSettlements;
  final List<CodStaffBalance> staffBalances;
  final List<CodSettlement> settlements;
  final List<CodTransaction> recentTransactions;

  factory CodOverview.fromJson(Map<String, dynamic> json) {
    final summary = jsonMap(json['summary']);
    return CodOverview(
      expectedPaise: asInt(summary['expected_paise']),
      collectedPaise: asInt(summary['collected_paise']),
      handedOverPaise: asInt(summary['handed_over_paise']),
      cashWithStaffPaise: asInt(summary['cash_with_staff_paise']),
      pendingVerificationPaise: asInt(summary['pending_verification_paise']),
      verifiedPaise: asInt(summary['verified_paise']),
      shortagePaise: asInt(summary['shortage_paise']),
      excessPaise: asInt(summary['excess_paise']),
      openSettlements: asInt(summary['open_settlements']),
      staffBalances: mapJsonList(json['staff_balances'], CodStaffBalance.fromJson),
      settlements: mapJsonList(json['settlements'], CodSettlement.fromJson),
      recentTransactions: mapJsonList(json['recent_transactions'], CodTransaction.fromJson),
    );
  }
}

class ReturnAdminItem {
  const ReturnAdminItem({required this.productName, required this.sku, required this.quantity, required this.lineTotalPaise});
  final String productName;
  final String sku;
  final int quantity;
  final int lineTotalPaise;
  factory ReturnAdminItem.fromJson(Map<String, dynamic> json) => ReturnAdminItem(
        productName: asString(json['product_name']),
        sku: asString(json['sku']),
        quantity: asInt(json['quantity']),
        lineTotalPaise: asInt(json['line_total_paise']),
      );
}

class ReturnAdmin {
  const ReturnAdmin({
    required this.id,
    required this.returnNumber,
    required this.status,
    required this.reason,
    required this.orderId,
    required this.orderNumber,
    required this.createdAt,
    this.description = '',
    this.evidencePath,
    this.customerName = '',
    this.customerPhone,
    this.orderTotalPaise = 0,
    this.deliveredAt,
    this.decidedAt,
    this.rejectionReason,
    this.receivedAt,
    this.resolutionNote,
    this.closedAt,
    this.items = const [],
  });
  final String id;
  final String returnNumber;
  final String status;
  final String reason;
  final String description;
  final String? evidencePath;
  final String orderId;
  final String orderNumber;
  final String customerName;
  final String? customerPhone;
  final int orderTotalPaise;
  final DateTime? deliveredAt;
  final DateTime createdAt;
  final DateTime? decidedAt;
  final String? rejectionReason;
  final DateTime? receivedAt;
  final String? resolutionNote;
  final DateTime? closedAt;
  final List<ReturnAdminItem> items;

  factory ReturnAdmin.fromJson(Map<String, dynamic> json) => ReturnAdmin(
        id: asString(json['id']),
        returnNumber: asString(json['return_number']),
        status: asString(json['status']),
        reason: asString(json['reason']),
        description: asString(json['description']),
        evidencePath: asNullableString(json['evidence_path']),
        orderId: asString(json['order_id']),
        orderNumber: asString(json['order_number']),
        customerName: asString(json['customer_name']),
        customerPhone: asNullableString(json['customer_phone']),
        orderTotalPaise: asInt(json['order_total_paise']),
        deliveredAt: asDate(json['delivered_at']),
        createdAt: asRequiredDate(json['created_at']),
        decidedAt: asDate(json['decided_at']),
        rejectionReason: asNullableString(json['rejection_reason']),
        receivedAt: asDate(json['received_at']),
        resolutionNote: asNullableString(json['resolution_note']),
        closedAt: asDate(json['closed_at']),
        items: mapJsonList(json['items'], ReturnAdminItem.fromJson),
      );
}

class AuditLog {
  const AuditLog({
    required this.id,
    required this.action,
    required this.entityType,
    required this.createdAt,
    this.actorName,
    this.actorRole,
    this.entityId,
    this.source,
    this.beforeData = const {},
    this.afterData = const {},
  });
  final String id;
  final String? actorName;
  final String? actorRole;
  final String action;
  final String entityType;
  final String? entityId;
  final Map<String, dynamic> beforeData;
  final Map<String, dynamic> afterData;
  final String? source;
  final DateTime createdAt;

  factory AuditLog.fromJson(Map<String, dynamic> json) => AuditLog(
        id: asString(json['id']),
        actorName: asNullableString(json['actor_name']),
        actorRole: asNullableString(json['actor_role']),
        action: asString(json['action']),
        entityType: asString(json['entity_type']),
        entityId: asNullableString(json['entity_id']),
        beforeData: jsonMap(json['before_data']),
        afterData: jsonMap(json['after_data']),
        source: asNullableString(json['source']),
        createdAt: asRequiredDate(json['created_at']),
      );
}

// ---------------------------------------------------------------------------
// Delivery staff read models
// ---------------------------------------------------------------------------
class StaffInfo {
  const StaffInfo({
    required this.userId,
    required this.displayName,
    required this.phone,
    required this.staffType,
    required this.isAvailable,
    this.partnerId,
    this.partnerName,
    this.capacityPerDay = 0,
    this.activeTasks = 0,
  });
  final String userId;
  final String displayName;
  final String phone;
  final String staffType;
  final String? partnerId;
  final String? partnerName;
  final int capacityPerDay;
  final bool isAvailable;
  final int activeTasks;

  factory StaffInfo.fromJson(Map<String, dynamic> json) => StaffInfo(
        userId: asString(json['user_id']),
        displayName: asString(json['display_name']),
        phone: asString(json['phone']),
        staffType: asString(json['staff_type']),
        partnerId: asNullableString(json['partner_id']),
        partnerName: asNullableString(json['partner_name']),
        capacityPerDay: asInt(json['capacity_per_day']),
        isAvailable: asBool(json['is_available']),
        activeTasks: asInt(json['active_tasks']),
      );
}

class StaffDashboard {
  const StaffDashboard({
    required this.staff,
    required this.activePickups,
    required this.activeDeliveries,
    required this.pickupsCompletedToday,
    required this.deliveriesCompletedToday,
    required this.codCollectedTodayPaise,
    required this.cashInCustodyPaise,
    required this.unreadNotifications,
  });
  final StaffInfo staff;
  final int activePickups;
  final int activeDeliveries;
  final int pickupsCompletedToday;
  final int deliveriesCompletedToday;
  final int codCollectedTodayPaise;
  final int cashInCustodyPaise;
  final int unreadNotifications;

  factory StaffDashboard.fromJson(Map<String, dynamic> json) => StaffDashboard(
        staff: StaffInfo.fromJson(jsonMap(json['staff'])),
        activePickups: asInt(json['active_pickups']),
        activeDeliveries: asInt(json['active_deliveries']),
        pickupsCompletedToday: asInt(json['pickups_completed_today']),
        deliveriesCompletedToday: asInt(json['deliveries_completed_today']),
        codCollectedTodayPaise: asInt(json['cod_collected_today_paise']),
        cashInCustodyPaise: asInt(json['cash_in_custody_paise']),
        unreadNotifications: asInt(json['unread_notifications']),
      );
}

class PickupTask {
  const PickupTask({
    required this.assignmentId,
    required this.pickupId,
    required this.pickupNumber,
    required this.assignmentStatus,
    required this.pickupStatus,
    required this.orderId,
    required this.orderNumber,
    required this.shipmentId,
    required this.shipmentNumber,
    required this.shipmentStatus,
    required this.packageCountExpected,
    required this.sealedPackages,
    required this.scannedPackages,
    required this.canAccept,
    required this.canScan,
    required this.canVerify,
    this.mode,
    this.assignedAt,
    this.respondedAt,
    this.expiresAt,
    this.pickupTown = '',
    this.pickupPincode = '',
    this.customerName = '',
    this.otpExpiresAt,
  });

  final String assignmentId;
  final String pickupId;
  final String pickupNumber;
  final String assignmentStatus;
  final String pickupStatus;
  final String? mode;
  final DateTime? assignedAt;
  final DateTime? respondedAt;
  final DateTime? expiresAt;
  final String orderId;
  final String orderNumber;
  final String shipmentId;
  final String shipmentNumber;
  final String shipmentStatus;
  final int packageCountExpected;
  final int sealedPackages;
  final int scannedPackages;
  final String pickupTown;
  final String pickupPincode;
  final String customerName;
  final DateTime? otpExpiresAt;
  final bool canAccept;
  final bool canScan;
  final bool canVerify;

  factory PickupTask.fromJson(Map<String, dynamic> json) => PickupTask(
        assignmentId: asString(json['assignment_id']),
        pickupId: asString(json['pickup_id']),
        pickupNumber: asString(json['pickup_number']),
        assignmentStatus: asString(json['assignment_status']),
        pickupStatus: asString(json['pickup_status']),
        mode: asNullableString(json['mode']),
        assignedAt: asDate(json['assigned_at']),
        respondedAt: asDate(json['responded_at']),
        expiresAt: asDate(json['expires_at']),
        orderId: asString(json['order_id']),
        orderNumber: asString(json['order_number']),
        shipmentId: asString(json['shipment_id']),
        shipmentNumber: asString(json['shipment_number']),
        shipmentStatus: asString(json['shipment_status']),
        packageCountExpected: asInt(json['package_count_expected']),
        sealedPackages: asInt(json['sealed_packages']),
        scannedPackages: asInt(json['scanned_packages']),
        pickupTown: asString(json['pickup_town']),
        pickupPincode: asString(json['pickup_pincode']),
        customerName: asString(json['customer_name']),
        otpExpiresAt: asDate(json['otp_expires_at']),
        canAccept: asBool(json['can_accept']),
        canScan: asBool(json['can_scan']),
        canVerify: asBool(json['can_verify']),
      );
}

class ScanEvent {
  const ScanEvent({required this.rawCode, required this.result, required this.message, this.packageId, this.scannedAt});
  final String rawCode;
  final String result;
  final String message;
  final String? packageId;
  final DateTime? scannedAt;
  factory ScanEvent.fromJson(Map<String, dynamic> json) => ScanEvent(
        rawCode: asString(json['raw_code']),
        result: asString(json['result']),
        message: asString(json['message']),
        packageId: asNullableString(json['package_id']),
        scannedAt: asDate(json['scanned_at']),
      );
}

class PickupSeller {
  const PickupSeller({this.name = '', this.legalName = '', this.address = '', this.phone = ''});
  final String name;
  final String legalName;
  final String address;
  final String phone;
  factory PickupSeller.fromJson(Map<String, dynamic> json) => PickupSeller(
        name: asString(json['name']),
        legalName: asString(json['legal_name']),
        address: asString(json['address']),
        phone: asString(json['phone']),
      );
}

class PickupOrderInfo {
  const PickupOrderInfo({
    required this.id,
    required this.orderNumber,
    required this.status,
    this.customerName = '',
    this.customerPhone = '',
    this.townName = '',
    this.district = '',
    this.state = '',
    this.pincode = '',
    this.totalPaise = 0,
    this.codAmountPaise = 0,
  });
  final String id;
  final String orderNumber;
  final String status;
  final String customerName;
  final String customerPhone;
  final String townName;
  final String district;
  final String state;
  final String pincode;
  final int totalPaise;
  final int codAmountPaise;

  factory PickupOrderInfo.fromJson(Map<String, dynamic> json) => PickupOrderInfo(
        id: asString(json['id']),
        orderNumber: asString(json['order_number']),
        status: asString(json['status']),
        customerName: asString(json['customer_name']),
        customerPhone: asString(json['customer_phone']),
        townName: asString(json['town_name']),
        district: asString(json['district']),
        state: asString(json['state']),
        pincode: asString(json['pincode']),
        totalPaise: asInt(json['total_paise']),
        codAmountPaise: asInt(json['cod_amount_paise']),
      );
}

class PickupDetailAssignment {
  const PickupDetailAssignment({required this.id, required this.status, this.mode, this.assignedAt, this.expiresAt, this.respondedAt});
  final String id;
  final String status;
  final String? mode;
  final DateTime? assignedAt;
  final DateTime? expiresAt;
  final DateTime? respondedAt;
  factory PickupDetailAssignment.fromJson(Map<String, dynamic> json) => PickupDetailAssignment(
        id: asString(json['id']),
        status: asString(json['status']),
        mode: asNullableString(json['mode']),
        assignedAt: asDate(json['assigned_at']),
        expiresAt: asDate(json['expires_at']),
        respondedAt: asDate(json['responded_at']),
      );
}

class PickupDetail {
  const PickupDetail({
    required this.assignment,
    required this.pickup,
    required this.shipment,
    required this.order,
    required this.seller,
    this.packages = const [],
    this.recentScans = const [],
    this.canAccept = false,
    this.canScan = false,
    this.canVerify = false,
    this.isVerified = false,
  });
  final PickupDetailAssignment assignment;
  final PickupInfo pickup;
  final ShipmentInfo shipment;
  final PickupOrderInfo order;
  final PickupSeller seller;
  final List<PackageInfo> packages;
  final List<ScanEvent> recentScans;
  final bool canAccept;
  final bool canScan;
  final bool canVerify;
  final bool isVerified;

  factory PickupDetail.fromJson(Map<String, dynamic> json) => PickupDetail(
        assignment: PickupDetailAssignment.fromJson(jsonMap(json['assignment'])),
        pickup: PickupInfo.fromJson(jsonMap(json['pickup'])),
        shipment: ShipmentInfo.fromJson(jsonMap(json['shipment'])),
        order: PickupOrderInfo.fromJson(jsonMap(json['order'])),
        seller: PickupSeller.fromJson(jsonMap(json['seller'])),
        packages: mapJsonList(json['packages'], PackageInfo.fromJson),
        recentScans: mapJsonList(json['recent_scans'], ScanEvent.fromJson),
        canAccept: asBool(json['can_accept']),
        canScan: asBool(json['can_scan']),
        canVerify: asBool(json['can_verify']),
        isVerified: asBool(json['is_verified']),
      );
}

class DeliveryTask {
  const DeliveryTask({
    required this.assignmentId,
    required this.shipmentId,
    required this.shipmentNumber,
    required this.assignmentStatus,
    required this.shipmentStatus,
    required this.orderId,
    required this.orderNumber,
    required this.packageCount,
    required this.totalPaise,
    required this.codAmountPaise,
    required this.attempts,
    required this.maxAttempts,
    required this.canAccept,
    required this.canStart,
    required this.canDeliver,
    this.mode,
    this.assignedAt,
    this.respondedAt,
    this.expiresAt,
    this.customerName = '',
    this.customerPhone,
    this.line1 = '',
    this.line2 = '',
    this.landmark = '',
    this.townName = '',
    this.district = '',
    this.state = '',
    this.pincode = '',
    this.otpExpiresAt,
  });

  final String assignmentId;
  final String shipmentId;
  final String shipmentNumber;
  final String assignmentStatus;
  final String shipmentStatus;
  final String? mode;
  final DateTime? assignedAt;
  final DateTime? respondedAt;
  final DateTime? expiresAt;
  final String orderId;
  final String orderNumber;
  final String customerName;
  final String? customerPhone;
  final String line1;
  final String line2;
  final String landmark;
  final String townName;
  final String district;
  final String state;
  final String pincode;
  final int packageCount;
  final int totalPaise;
  final int codAmountPaise;
  final int attempts;
  final int maxAttempts;
  final DateTime? otpExpiresAt;
  final bool canAccept;
  final bool canStart;
  final bool canDeliver;

  String get addressLine => [line1, if (line2.isNotEmpty) line2, if (landmark.isNotEmpty) landmark, townName, district, state, pincode]
      .where((part) => part.trim().isNotEmpty)
      .join(', ');

  factory DeliveryTask.fromJson(Map<String, dynamic> json) => DeliveryTask(
        assignmentId: asString(json['assignment_id']),
        shipmentId: asString(json['shipment_id']),
        shipmentNumber: asString(json['shipment_number']),
        assignmentStatus: asString(json['assignment_status']),
        shipmentStatus: asString(json['shipment_status']),
        mode: asNullableString(json['mode']),
        assignedAt: asDate(json['assigned_at']),
        respondedAt: asDate(json['responded_at']),
        expiresAt: asDate(json['expires_at']),
        orderId: asString(json['order_id']),
        orderNumber: asString(json['order_number']),
        customerName: asString(json['customer_name']),
        customerPhone: asNullableString(json['customer_phone']),
        line1: asString(json['line1']),
        line2: asString(json['line2']),
        landmark: asString(json['landmark']),
        townName: asString(json['town_name']),
        district: asString(json['district']),
        state: asString(json['state']),
        pincode: asString(json['pincode']),
        packageCount: asInt(json['package_count']),
        totalPaise: asInt(json['total_paise']),
        codAmountPaise: asInt(json['cod_amount_paise']),
        attempts: asInt(json['attempts']),
        maxAttempts: asInt(json['max_attempts'], 3),
        otpExpiresAt: asDate(json['otp_expires_at']),
        canAccept: asBool(json['can_accept']),
        canStart: asBool(json['can_start']),
        canDeliver: asBool(json['can_deliver']),
      );
}

class DeliveryAttemptInfo {
  const DeliveryAttemptInfo({required this.attemptNumber, required this.reason, this.notes, this.attemptedAt, this.nextRetryAt});
  final int attemptNumber;
  final String reason;
  final String? notes;
  final DateTime? attemptedAt;
  final DateTime? nextRetryAt;
  factory DeliveryAttemptInfo.fromJson(Map<String, dynamic> json) => DeliveryAttemptInfo(
        attemptNumber: asInt(json['attempt_number']),
        reason: asString(json['reason']),
        notes: asNullableString(json['notes']),
        attemptedAt: asDate(json['attempted_at']),
        nextRetryAt: asDate(json['next_retry_at']),
      );
}

class DeliveryEventInfo {
  const DeliveryEventInfo({required this.eventType, required this.newStatus, required this.createdAt, this.locationText});
  final String eventType;
  final String newStatus;
  final DateTime createdAt;
  final String? locationText;
  factory DeliveryEventInfo.fromJson(Map<String, dynamic> json) => DeliveryEventInfo(
        eventType: asString(json['event_type']),
        newStatus: asString(json['new_status']),
        createdAt: asRequiredDate(json['created_at']),
        locationText: asNullableString(json['location_text']),
      );
}

class DeliveryOrderInfo {
  const DeliveryOrderInfo({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.recipientName,
    required this.phone,
    required this.line1,
    required this.townName,
    required this.district,
    required this.state,
    required this.pincode,
    required this.totalPaise,
    required this.codAmountPaise,
    this.line2 = '',
    this.landmark = '',
    this.customerNote = '',
  });
  final String id;
  final String orderNumber;
  final String status;
  final String recipientName;
  final String phone;
  final String line1;
  final String line2;
  final String landmark;
  final String townName;
  final String district;
  final String state;
  final String pincode;
  final int totalPaise;
  final int codAmountPaise;
  final String customerNote;

  String get addressLine => [line1, if (line2.isNotEmpty) line2, if (landmark.isNotEmpty) landmark, townName, district, state, pincode]
      .where((part) => part.trim().isNotEmpty)
      .join(', ');

  factory DeliveryOrderInfo.fromJson(Map<String, dynamic> json) => DeliveryOrderInfo(
        id: asString(json['id']),
        orderNumber: asString(json['order_number']),
        status: asString(json['status']),
        recipientName: asString(json['recipient_name']),
        phone: asString(json['phone']),
        line1: asString(json['line1']),
        line2: asString(json['line2']),
        landmark: asString(json['landmark']),
        townName: asString(json['town_name']),
        district: asString(json['district']),
        state: asString(json['state']),
        pincode: asString(json['pincode']),
        totalPaise: asInt(json['total_paise']),
        codAmountPaise: asInt(json['cod_amount_paise']),
        customerNote: asString(json['customer_note']),
      );
}

class DeliveryDetail {
  const DeliveryDetail({
    required this.assignment,
    required this.shipment,
    required this.order,
    this.items = const [],
    this.packages = const [],
    this.attempts = const [],
    this.events = const [],
    this.otpExpiresAt,
    this.maxAttempts = 3,
    this.requirePhoto = false,
    this.canAccept = false,
    this.canStart = false,
    this.canDeliver = false,
  });
  final PickupDetailAssignment assignment;
  final ShipmentInfo shipment;
  final DeliveryOrderInfo order;
  final List<OrderItem> items;
  final List<PackageInfo> packages;
  final List<DeliveryAttemptInfo> attempts;
  final List<DeliveryEventInfo> events;
  final DateTime? otpExpiresAt;
  final int maxAttempts;
  final bool requirePhoto;
  final bool canAccept;
  final bool canStart;
  final bool canDeliver;

  factory DeliveryDetail.fromJson(Map<String, dynamic> json) => DeliveryDetail(
        assignment: PickupDetailAssignment.fromJson(jsonMap(json['assignment'])),
        shipment: ShipmentInfo.fromJson(jsonMap(json['shipment'])),
        order: DeliveryOrderInfo.fromJson(jsonMap(json['order'])),
        items: mapJsonList(json['items'], OrderItem.fromJson),
        packages: mapJsonList(json['packages'], PackageInfo.fromJson),
        attempts: mapJsonList(json['attempts'], DeliveryAttemptInfo.fromJson),
        events: mapJsonList(json['events'], DeliveryEventInfo.fromJson),
        otpExpiresAt: asDate(json['otp_expires_at']),
        maxAttempts: asInt(json['max_attempts'], 3),
        requirePhoto: asBool(json['require_photo']),
        canAccept: asBool(json['can_accept']),
        canStart: asBool(json['can_start']),
        canDeliver: asBool(json['can_deliver']),
      );
}

class UnsettledShipment {
  const UnsettledShipment({
    required this.shipmentId,
    required this.shipmentNumber,
    required this.orderId,
    required this.orderNumber,
    required this.expectedPaise,
    required this.collectedPaise,
    required this.netPaise,
    this.lastCollectedAt,
  });
  final String shipmentId;
  final String shipmentNumber;
  final String orderId;
  final String orderNumber;
  final int expectedPaise;
  final int collectedPaise;
  final int netPaise;
  final DateTime? lastCollectedAt;

  factory UnsettledShipment.fromJson(Map<String, dynamic> json) => UnsettledShipment(
        shipmentId: asString(json['shipment_id']),
        shipmentNumber: asString(json['shipment_number']),
        orderId: asString(json['order_id']),
        orderNumber: asString(json['order_number']),
        expectedPaise: asInt(json['expected_paise']),
        collectedPaise: asInt(json['collected_paise']),
        netPaise: asInt(json['net_paise']),
        lastCollectedAt: asDate(json['last_collected_at']),
      );
}

class RecentSettlement {
  const RecentSettlement({
    required this.id,
    required this.settlementNumber,
    required this.expectedPaise,
    required this.collectedPaise,
    required this.handedOverPaise,
    required this.countedPaise,
    required this.shortagePaise,
    required this.excessPaise,
    required this.status,
    required this.declaredAt,
    this.verifiedAt,
  });
  final String id;
  final String settlementNumber;
  final int expectedPaise;
  final int collectedPaise;
  final int handedOverPaise;
  final int countedPaise;
  final int shortagePaise;
  final int excessPaise;
  final String status;
  final DateTime declaredAt;
  final DateTime? verifiedAt;

  factory RecentSettlement.fromJson(Map<String, dynamic> json) => RecentSettlement(
        id: asString(json['id']),
        settlementNumber: asString(json['settlement_number']),
        expectedPaise: asInt(json['expected_paise']),
        collectedPaise: asInt(json['collected_paise']),
        handedOverPaise: asInt(json['handed_over_paise']),
        countedPaise: asInt(json['counted_paise']),
        shortagePaise: asInt(json['shortage_paise']),
        excessPaise: asInt(json['excess_paise']),
        status: asString(json['status']),
        declaredAt: asRequiredDate(json['declared_at']),
        verifiedAt: asDate(json['verified_at']),
      );
}

class StaffCodSummary {
  const StaffCodSummary({
    required this.cashInCustodyPaise,
    this.pendingSettlements = const [],
    this.unsettledShipments = const [],
    this.recentSettlements = const [],
  });
  final int cashInCustodyPaise;
  final List<RecentSettlement> pendingSettlements;
  final List<UnsettledShipment> unsettledShipments;
  final List<RecentSettlement> recentSettlements;

  factory StaffCodSummary.fromJson(Map<String, dynamic> json) => StaffCodSummary(
        cashInCustodyPaise: asInt(json['cash_in_custody_paise']),
        pendingSettlements: mapJsonList(json['pending_settlements'], RecentSettlement.fromJson),
        unsettledShipments: mapJsonList(json['unsettled_shipments'], UnsettledShipment.fromJson),
        recentSettlements: mapJsonList(json['recent_settlements'], RecentSettlement.fromJson),
      );
}

// ---------------------------------------------------------------------------
// Partner read models
// ---------------------------------------------------------------------------
class PartnerDashboard {
  const PartnerDashboard({
    required this.partnerId,
    required this.partnerName,
    required this.activeStaff,
    required this.availableStaff,
    required this.pendingPickups,
    required this.activeDeliveries,
    required this.deliveredToday,
    required this.codOutstandingPaise,
    this.recentTasks = const [],
  });
  final String partnerId;
  final String partnerName;
  final int activeStaff;
  final int availableStaff;
  final int pendingPickups;
  final int activeDeliveries;
  final int deliveredToday;
  final int codOutstandingPaise;
  final List<Map<String, dynamic>> recentTasks;

  factory PartnerDashboard.fromJson(Map<String, dynamic> json) => PartnerDashboard(
        partnerId: asString(json['partner_id']),
        partnerName: asString(json['partner_name']),
        activeStaff: asInt(json['active_staff']),
        availableStaff: asInt(json['available_staff']),
        pendingPickups: asInt(json['pending_pickups']),
        activeDeliveries: asInt(json['active_deliveries']),
        deliveredToday: asInt(json['delivered_today']),
        codOutstandingPaise: asInt(json['cod_outstanding_paise']),
        recentTasks: jsonList(json['recent_tasks']),
      );
}

class PartnerStaff {
  const PartnerStaff({
    required this.userId,
    required this.displayName,
    required this.phone,
    required this.status,
    required this.isAdmin,
    required this.canManagePartnerStaff,
    required this.isAvailable,
    this.capacityPerDay = 0,
    this.activeTasks = 0,
  });
  final String userId;
  final String displayName;
  final String phone;
  final String status;
  final bool isAdmin;
  final bool canManagePartnerStaff;
  final bool isAvailable;
  final int capacityPerDay;
  final int activeTasks;

  factory PartnerStaff.fromJson(Map<String, dynamic> json) => PartnerStaff(
        userId: asString(json['user_id']),
        displayName: asString(json['display_name']),
        phone: asString(json['phone']),
        status: asString(json['status']),
        isAdmin: asBool(json['is_admin']),
        canManagePartnerStaff: asBool(json['can_manage_partner_staff']),
        isAvailable: asBool(json['is_available']),
        capacityPerDay: asInt(json['capacity_per_day']),
        activeTasks: asInt(json['active_tasks']),
      );
}

class PartnerTask {
  const PartnerTask({
    required this.taskType,
    required this.assignmentId,
    required this.staffName,
    required this.status,
    required this.orderId,
    required this.orderNumber,
    required this.shipmentId,
    required this.shipmentNumber,
    this.pickupNumber,
    this.townName = '',
    this.pincode = '',
    this.codAmountPaise = 0,
    this.createdAt,
  });
  final String taskType;
  final String assignmentId;
  final String staffName;
  final String status;
  final String orderId;
  final String orderNumber;
  final String shipmentId;
  final String shipmentNumber;
  final String? pickupNumber;
  final String townName;
  final String pincode;
  final int codAmountPaise;
  final DateTime? createdAt;

  factory PartnerTask.fromJson(Map<String, dynamic> json) => PartnerTask(
        taskType: asString(json['task_type']),
        assignmentId: asString(json['assignment_id']),
        staffName: asString(json['staff_name']),
        status: asString(json['status']),
        orderId: asString(json['order_id']),
        orderNumber: asString(json['order_number']),
        shipmentId: asString(json['shipment_id']),
        shipmentNumber: asString(json['shipment_number']),
        pickupNumber: asNullableString(json['pickup_number']),
        townName: asString(json['town_name']),
        pincode: asString(json['pincode']),
        codAmountPaise: asInt(json['cod_amount_paise']),
        createdAt: asDate(json['created_at']),
      );
}
