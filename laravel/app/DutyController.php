<?php

namespace App\Http\Controllers;

use App\Models\Declaration;
use Illuminate\Http\Request;

/**
 * Superseded copy of app/Http/Controllers/DutyController.php.
 *
 * Not built into the image and not routed. Retained only as a
 * single-file reference; edit the copy under Http/Controllers.
 */
class DutyController extends Controller
{
    public function calculate(Request $request)
    {
        // Failure injection for the resilience demo. With FAIL_MODE=on
        // the router must still return the COBOL answer unaffected in
        // SHADOW mode.
        $failMode = env('FAIL_MODE', 'off');
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
