<?php

namespace App\Http\Controllers;

use App\Models\Declaration;
use Illuminate\Http\Request;

/**
 * JKDM SMK POC - duty calculation, PHP/Laravel implementation.
 *
 * This is the redevelopment candidate: the same fiscal calculation
 * the COBOL core performs, reimplemented in the tender's target
 * language (SMK TS3-02).
 *
 * ARITHMETIC NOTE - READ BEFORE "FIXING" THIS
 * -------------------------------------------
 * This uses native PHP floats and rounds ONCE at the total, where
 * the COBOL rounds each line to 2dp before accumulating. On
 * multi-line declarations the two diverge by a cent or so.
 *
 * That is deliberate, and it is what a developer reaches for by
 * default. If someone in the workshop says "you should have used
 * bcmath" - that is the correct conclusion, and exactly the kind of
 * finding the SMK 5.7 fiscal-equivalence gate exists to force
 * BEFORE cutover rather than after.
 *
 * Do not fix it before the session.
 */
class DutyController extends Controller
{
    public function calculate(Request $request)
    {
        // Failure injection for the resilience demo. In SHADOW mode the
        // router must still return the COBOL answer, unaffected.
        //
        // Read from a file rather than the environment so it can be
        // flipped live with scripts/php-fail.sh - restarting the
        // container mid-demo would prove nothing, because a restart
        // hides exactly the behaviour under test.
        $failMode = 'off';
        if (is_readable('/opt/app/storage/failmode')) {
            $failMode = trim(file_get_contents('/opt/app/storage/failmode'));
        }
        if ($failMode === 'on') {
            return response()->json(['error' => 'service unavailable'], 500);
        }
        if ($failMode === 'hang') {
            sleep(30);
        }

        $ref = trim($request->input('declarationRef', ''));

        if ($ref === '') {
            return response()->json(['error' => 'declarationRef required'], 400);
        }

        $declaration = Declaration::with(['lines.tariff'])
            ->where('decl_ref', $ref)
            ->first();

        if (!$declaration) {
            return response()->json(['error' => 'declaration not found'], 404);
        }

        $totalDuty    = 0.0;   // accumulated at FULL float precision
        $totalSst     = 0.0;
        $totalValue   = 0.0;
        $prefApplied  = false;
        $lineDetails  = [];

        foreach ($declaration->lines as $line) {
            $tariff = $line->tariff;

            $rate = (float) $tariff->duty_rate;

            $fta = $declaration->ftaRuleFor($tariff->hs_code);

            // Boundary condition: strictly greater-than.
            // The COBOL uses >= . A declaration sitting exactly ON the
            // threshold gets different treatment. Deliberate.
            if ($fta && (float) $declaration->local_pct > (float) $fta->min_local_pct) {
                $rate = (float) $fta->pref_rate;
                $prefApplied = true;
            }

            $customsValue = (float) $line->customs_value;

            $lineDuty = $customsValue * $rate;
            $lineSst  = ($customsValue + $lineDuty) * (float) $tariff->sst_rate;

            $totalDuty  += $lineDuty;    // no per-line rounding
            $totalSst   += $lineSst;
            $totalValue += $customsValue;

            $lineDetails[] = [
                'lineNo'        => (int) $line->line_no,
                'hsCode'        => $tariff->hs_code,
                'hsDescription' => $tariff->description,   // full, untruncated
                'rateApplied'   => round($rate, 4),
                'customsValue'  => round($customsValue, 2),
                'lineDuty'      => round($lineDuty, 2),
                'lineSst'       => round($lineSst, 2),
            ];
        }

        // Rounded once, at the end.
        $totalDuty = round($totalDuty, 2);
        $totalSst  = round($totalSst, 2);

        return response()->json([
            'status'            => 'OK',
            'declarationRef'    => $declaration->decl_ref,
            'lineCount'         => count($lineDetails),
            'totalCustomsValue' => round($totalValue, 2),
            'totalDutyAmount'   => $totalDuty,
            'totalSstAmount'    => $totalSst,
            'totalPayable'      => round($totalDuty + $totalSst, 2),
            'preferenceApplied' => $prefApplied,
            'calculatedAt'      => now()->toIso8601String(),   // ISO-8601 + TZ
            'lines'             => $lineDetails,
            'backend'           => 'PHP',
        ]);
    }

    public function health()
    {
        return response()->json(['status' => 'UP']);
    }
}
