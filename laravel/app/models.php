<?php
/**
 * JKDM SMK POC - Eloquent models.
 *
 * Split into separate files by the Dockerfile at build time.
 * Kept together here so the contrast with the IRIS equivalent is
 * visible in one screen during the enablement segment (spec 8.3):
 *
 *   Laravel + Postgres : migration + model + physical table
 *                        = three artefacts kept in sync by hand
 *   IRIS               : one class definition that IS the object,
 *                        the SQL table, and the storage
 *
 * ---8<--- app/Models/Declaration.php
 */

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Declaration extends Model
{
    protected $table = 'declaration';
    protected $primaryKey = 'decl_ref';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;

    public function lines()
    {
        return $this->hasMany(DeclarationLine::class, 'decl_ref', 'decl_ref')
                    ->orderBy('line_no');
    }

    public function ftaRuleFor(string $hsCode)
    {
        if (empty($this->fta_claimed)) {
            return null;
        }

        return FtaRule::where('fta_code', $this->fta_claimed)
            ->where('hs_code', $hsCode)
            ->where('origin_country', $this->origin_country)
            ->first();
    }
}

/**
 * ---8<--- app/Models/DeclarationLine.php
 */
class DeclarationLine extends Model
{
    protected $table = 'declaration_line';
    public $timestamps = false;
    public $incrementing = false;

    public function tariff()
    {
        return $this->belongsTo(TariffRate::class, 'hs_code', 'hs_code');
    }
}

/**
 * ---8<--- app/Models/TariffRate.php
 */
class TariffRate extends Model
{
    protected $table = 'tariff_rate';
    protected $primaryKey = 'hs_code';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;
}

/**
 * ---8<--- app/Models/FtaRule.php
 */
class FtaRule extends Model
{
    protected $table = 'fta_rule';
    public $timestamps = false;
    public $incrementing = false;
}
