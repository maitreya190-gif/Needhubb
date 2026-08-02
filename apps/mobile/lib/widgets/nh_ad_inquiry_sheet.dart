import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_client.dart';
import '../services/ads_api.dart';
import '../theme/tokens.dart';

class NhAdInquirySheet extends StatefulWidget {
  const NhAdInquirySheet({super.key});

  @override
  State<NhAdInquirySheet> createState() => _NhAdInquirySheetState();
}

class _NhAdInquirySheetState extends State<NhAdInquirySheet> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _productController = TextEditingController();
  final _messageController = TextEditingController();
  
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _productController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final product = _productController.text.trim();
    
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || product.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Name and Product are required', style: GoogleFonts.hankenGrotesk()),
          backgroundColor: Colors.red.shade800,
        )
      );
      return;
    }
    if (email.isEmpty && phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please provide an email or phone number', style: GoogleFonts.hankenGrotesk()),
          backgroundColor: Colors.red.shade800,
        )
      );
      return;
    }

    setState(() => _submitting = true);
    
    try {
      await AdsApi(ApiClient()).submitInquiry(
        name: name,
        email: email,
        phone: phone,
        product: product,
        message: _messageController.text.trim(),
      );
      
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitted = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit inquiry. Please try again later.', style: GoogleFonts.hankenGrotesk()),
            backgroundColor: Colors.red.shade800,
          )
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad + 20),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: _submitted ? _buildSuccessView(t) : _buildFormView(t),
    );
  }

  Widget _buildFormView(NeedHubTokens t) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: t.rail,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          Text(
            'Advertise on NeedHub',
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: t.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Fill in your details and we\'ll get back to you',
            style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted),
          ),
          const SizedBox(height: 20),
          
          _buildTextField(t, 'Name *', _nameController),
          const SizedBox(height: 12),
          _buildTextField(t, 'Email', _emailController),
          const SizedBox(height: 12),
          _buildTextField(t, 'Phone Number', _phoneController),
          const SizedBox(height: 12),
          _buildTextField(t, 'Product/Service *', _productController),
          const SizedBox(height: 12),
          _buildTextField(t, 'Additional details', _messageController, maxLines: 3),
          
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: NeedHubTokens.ochre,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                textStyle: GoogleFonts.bricolageGrotesque(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 24, height: 24, 
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
                    )
                  : const Text('Submit Inquiry'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(NeedHubTokens t, String hint, TextEditingController controller, {int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: t.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.rail, width: 1.5),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.ink),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(14),
          filled: false,
        ),
      ),
    );
  }

  Widget _buildSuccessView(NeedHubTokens t) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: NeedHubTokens.ochre.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.check_rounded,
              color: NeedHubTokens.ochre, size: 30),
        ),
        const SizedBox(height: 16),
        Text(
          'Inquiry Sent',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: t.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'We\'ll contact you soon!',
          style: GoogleFonts.hankenGrotesk(
            fontSize: 14,
            color: t.muted,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Done',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}
