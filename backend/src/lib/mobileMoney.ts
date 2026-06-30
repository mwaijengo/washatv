/** Tanzania mobile-money network from national `0XXXXXXXXX` phone. */
export type TzMobileNetwork = 'mpesa' | 'airtel' | 'tigo' | 'halotel' | 'unknown';

export function detectTzMobileNetwork(localPhone: string): TzMobileNetwork {
  const digits = localPhone.replace(/\D/g, '');
  let local = digits;
  if (local.startsWith('255') && local.length >= 12) {
    local = `0${local.slice(3, 12)}`;
  } else if (local.length === 9 && /^[67]/.test(local)) {
    local = `0${local}`;
  }
  if (!/^0[67]\d{8}$/.test(local)) return 'unknown';

  const prefix = local.slice(0, 3);
  if (['061', '062', '063'].includes(prefix)) return 'halotel';
  if (['065', '067', '071', '073'].includes(prefix)) return 'tigo';
  if (['068', '069'].includes(prefix)) return 'airtel';
  if (['074', '075', '076', '077', '078'].includes(prefix)) return 'mpesa';
  if (local.startsWith('06')) return 'halotel';
  if (local.startsWith('07')) return 'mpesa';
  return 'unknown';
}

export function mobileMoneyMethodLabel(network: TzMobileNetwork): string {
  switch (network) {
    case 'mpesa':
      return 'M-Pesa';
    case 'airtel':
      return 'Airtel Money';
    case 'tigo':
      return 'Mixx by Yas';
    case 'halotel':
      return 'Halotel';
    default:
      return 'Mobile Money';
  }
}

export function paymentPromptForPhone(localPhone: string): string {
  const network = detectTzMobileNetwork(localPhone);
  switch (network) {
    case 'mpesa':
      return 'Angalia simu yako — thibitisha PIN ya M-Pesa.';
    case 'airtel':
      return 'Angalia simu yako — thibitisha PIN ya Airtel Money.';
    case 'tigo':
      return 'Angalia simu yako — thibitisha PIN ya Mixx by Yas.';
    case 'halotel':
      return 'Angalia simu yako — thibitisha PIN ya Halotel.';
    default:
      return 'Angalia simu yako — thibitisha PIN (M-Pesa, Mixx, Airtel Money, Halotel).';
  }
}
