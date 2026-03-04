/**
 * Payment Routes — SePay webhook + QR generation
 */
import { Router, Request, Response } from 'express';
import { db } from '../config/firebase.js';
import { COLLECTIONS } from '../config/constants.js';
import * as sessionService from '../services/sessionService.js';
import * as logService from '../services/logService.js';

const router = Router();

/**
 * POST /api/payment/create-qr
 * Generate payment QR for a station
 * Called by tablet to get QR code data
 */
router.post('/create-qr', async (req: Request, res: Response) => {
  try {
    const { stationId, amount, sessionId } = req.body;
    if (!stationId || !amount) {
      res.status(400).json({ success: false, error: 'stationId and amount required' });
      return;
    }

    const configDoc = await db.collection(COLLECTIONS.CONFIG).doc('main').get();
    const config = configDoc.data();

    if (amount < (config?.minDeposit || 30000)) {
      res.status(400).json({ success: false, error: `Minimum: ${config?.minDeposit || 30000}đ` });
      return;
    }

    // Generate unique reference code for this payment
    const refCode = `RX${stationId.replace(/\D/g, '')}${Date.now().toString(36).toUpperCase()}`;

    // Store pending payment
    await db.collection('pending_payments').doc(refCode).set({
      refCode,
      stationId,
      sessionId: sessionId || null,
      amount,
      status: 'PENDING',
      createdAt: Date.now(),
      expiresAt: Date.now() + 15 * 60 * 1000, // 15 min expiry
    });

    // Build QR content (VietQR format)
    // In production, this would call SePay API
    const bankAccount = config?.sepay?.bankAccount || '0123456789';
    const bankCode = config?.sepay?.bankCode || 'MB';
    const qrContent = `https://img.vietqr.io/image/${bankCode}-${bankAccount}-compact2.png?amount=${amount}&addInfo=${refCode}`;

    res.json({
      success: true,
      data: {
        refCode,
        qrContent,
        qrUrl: qrContent, // URL to QR image
        amount,
        bankAccount,
        bankCode,
        transferContent: refCode,
        expiresAt: Date.now() + 15 * 60 * 1000,
      },
    });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

/**
 * POST /api/payment/sepay-webhook
 * SePay calls this when payment is received
 */
router.post('/sepay-webhook', async (req: Request, res: Response) => {
  try {
    const { content, transferAmount, transferType, referenceCode, gateway, transactionDate, accountNumber } = req.body;

    console.log('[SePay Webhook]', JSON.stringify(req.body).slice(0, 500));

    // Only process incoming transfers
    if (transferType !== 'in') {
      res.json({ success: true, message: 'Ignored outgoing transfer' });
      return;
    }

    // Find matching pending payment by reference code in content
    const pendingSnap = await db.collection('pending_payments')
      .where('status', '==', 'PENDING')
      .get();

    let matchedPayment: any = null;
    let matchedRef = '';

    pendingSnap.forEach((doc: any) => {
      const data = doc.data();
      // Check if the transfer content contains our reference code
      if (content && content.includes(data.refCode)) {
        matchedPayment = data;
        matchedRef = data.refCode;
      }
    });

    if (!matchedPayment) {
      console.log('[SePay] No matching pending payment for content:', content);
      // Still return 200 to SePay
      res.json({ success: true, message: 'No matching payment found' });
      return;
    }

    // Verify amount
    if (transferAmount < matchedPayment.amount) {
      console.log('[SePay] Amount mismatch:', transferAmount, 'expected:', matchedPayment.amount);
      res.json({ success: true, message: 'Amount insufficient' });
      return;
    }

    // Mark payment as completed
    await db.collection('pending_payments').doc(matchedRef).update({
      status: 'COMPLETED',
      actualAmount: transferAmount,
      sepayData: req.body,
      completedAt: Date.now(),
    });

    // Create or update session
    if (matchedPayment.sessionId) {
      // Add to existing session
      await sessionService.addDeposit(matchedPayment.sessionId, transferAmount, referenceCode);
    } else {
      // Create new session
      await sessionService.createSession(matchedPayment.stationId, transferAmount, referenceCode);
    }

    await logService.log(matchedPayment.stationId, 'PAYMENT',
      `SePay: nhận ${transferAmount.toLocaleString()}đ`, { refCode: matchedRef, gateway });

    res.json({ success: true, message: 'Payment processed' });
  } catch (error: any) {
    console.error('[SePay Webhook Error]', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

/**
 * GET /api/payment/check/:refCode
 * Tablet polls this to check if payment is confirmed
 */
router.get('/check/:refCode', async (req: Request, res: Response) => {
  try {
    const paymentDoc = await db.collection('pending_payments').doc(req.params.refCode).get();
    if (!paymentDoc.exists) {
      res.status(404).json({ success: false, error: 'Payment not found' });
      return;
    }

    const payment = paymentDoc.data()!;
    res.json({
      success: true,
      data: {
        status: payment.status,
        amount: payment.actualAmount || payment.amount,
        sessionId: payment.sessionId,
      },
    });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

/**
 * POST /api/payment/demo-confirm
 * Demo mode: manually confirm a payment (for testing)
 */
router.post('/demo-confirm', async (req: Request, res: Response) => {
  try {
    const { refCode, amount } = req.body;

    const paymentDoc = await db.collection('pending_payments').doc(refCode).get();
    if (!paymentDoc.exists) {
      res.status(404).json({ success: false, error: 'Payment not found' });
      return;
    }

    const payment = paymentDoc.data()!;
    const confirmAmount = amount || payment.amount;

    // Mark completed
    await db.collection('pending_payments').doc(refCode).update({
      status: 'COMPLETED',
      actualAmount: confirmAmount,
      completedAt: Date.now(),
    });

    // Create/update session
    if (payment.sessionId) {
      await sessionService.addDeposit(payment.sessionId, confirmAmount);
    } else {
      await sessionService.createSession(payment.stationId, confirmAmount);
    }

    await logService.log(payment.stationId, 'PAYMENT',
      `[Demo] Xác nhận ${confirmAmount.toLocaleString()}đ`, { refCode });

    res.json({ success: true, message: `Confirmed ${confirmAmount}đ for station ${payment.stationId}` });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

export default router;
